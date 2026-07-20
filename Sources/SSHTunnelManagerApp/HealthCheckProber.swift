import Foundation
import Network
import SSHTunnelCore

struct RuleHealthCheckKey: Hashable, Sendable {
    let tunnelID: TunnelConfig.ID
    let ruleID: TunnelForwardRule.ID
}

enum RuleHealthCheckPhase: Equatable, Sendable {
    case waiting
    case healthy
    case unhealthy
}

enum HealthProbeFailureCategory: String, Equatable, Sendable {
    case connectionRefused
    case timeout
    case tls
    case httpStatus
    case protocolError
    case authenticationRequired
    case connectionClosed
    case network
    case cancelled
}

enum HealthProbeResult: Equatable, Sendable {
    case success
    case failure(HealthProbeFailureCategory)
}

struct RuleHealthCheckRuntimeState: Equatable, Sendable {
    static let failureThreshold = 3

    var phase: RuleHealthCheckPhase = .waiting
    var consecutiveFailures = 0
    var lastCheckedAt: Date?
    var failureCategory: HealthProbeFailureCategory?

    mutating func record(_ result: HealthProbeResult, at date: Date) {
        guard result != .failure(.cancelled) else { return }
        lastCheckedAt = date
        switch result {
        case .success:
            phase = .healthy
            consecutiveFailures = 0
            failureCategory = nil
        case .failure(let category):
            consecutiveFailures += 1
            failureCategory = category
            if consecutiveFailures >= Self.failureThreshold {
                phase = .unhealthy
            }
        }
    }

    mutating func resetToWaiting() {
        phase = .waiting
        consecutiveFailures = 0
        lastCheckedAt = nil
        failureCategory = nil
    }
}

enum TunnelHealthAggregatePhase: Equatable, Sendable {
    case notConfigured
    case waiting
    case healthy
    case unhealthy
}

struct HealthProbeRequest: Equatable, Sendable {
    let key: RuleHealthCheckKey
    let generation: UInt64
    let listenerHost: String
    let listenerPort: Int
    let configuration: TunnelHealthCheckConfiguration

    var connectionHost: String {
        let value = listenerHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "*", "0.0.0.0":
            return "127.0.0.1"
        case "::", "[::]":
            return "::1"
        default:
            guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
            return String(value.dropFirst().dropLast())
        }
    }
}

protocol HealthProbing: Sendable {
    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult
}

struct SystemHealthProber: HealthProbing {
    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        do {
            switch request.configuration.kind {
            case .tcp:
                try await withHealthProbeTimeout(request.configuration.timeout) {
                    let session = NWHealthProbeSession(
                        host: request.connectionHost,
                        port: request.listenerPort
                    )
                    try await session.connect()
                    session.cancel()
                }
            case .socks5:
                try await withHealthProbeTimeout(request.configuration.timeout) {
                    let session = NWHealthProbeSession(
                        host: request.connectionHost,
                        port: request.listenerPort
                    )
                    defer { session.cancel() }
                    try await session.connect()
                    try await session.send(Data([0x05, 0x01, 0x00]))
                    let response = try await session.receive(count: 2)
                    guard response.count == 2, response[0] == 0x05 else {
                        throw HealthProbeOperationError.protocolError
                    }
                    guard response[1] == 0x00 else {
                        throw HealthProbeOperationError.authenticationRequired
                    }
                }
            case .http:
                guard let url = request.configuration.url else {
                    return .failure(.protocolError)
                }
                let status = try await withHealthProbeTimeout(request.configuration.timeout) {
                    try await HTTPHealthProbeOperation().statusCode(
                        for: url,
                        timeout: request.configuration.timeout
                    )
                }
                guard (200...399).contains(status) else {
                    return .failure(.httpStatus)
                }
            }
            return Task.isCancelled ? .failure(.cancelled) : .success
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch HealthProbeOperationError.timedOut {
            return .failure(.timeout)
        } catch HealthProbeOperationError.authenticationRequired {
            return .failure(.authenticationRequired)
        } catch HealthProbeOperationError.protocolError {
            return .failure(.protocolError)
        } catch HealthProbeOperationError.connectionClosed {
            return .failure(.connectionClosed)
        } catch let error as NWError {
            return .failure(Self.category(for: error))
        } catch let error as URLError {
            return .failure(Self.category(for: error))
        } catch {
            return .failure(.network)
        }
    }

    static func category(for error: NWError) -> HealthProbeFailureCategory {
        if case .posix(.ECONNREFUSED) = error { return .connectionRefused }
        if case .posix(.ETIMEDOUT) = error { return .timeout }
        return .network
    }

    static func category(for error: URLError) -> HealthProbeFailureCategory {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost:
            return .connectionRefused
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .secureConnectionFailed:
            return .tls
        case .cancelled:
            return .cancelled
        default:
            return .network
        }
    }
}

private enum HealthProbeOperationError: Error {
    case timedOut
    case protocolError
    case authenticationRequired
    case connectionClosed
}

private func withHealthProbeTimeout<Output: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    try await withThrowingTaskGroup(of: Output.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw HealthProbeOperationError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}

private final class NWHealthProbeSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ssh-tunnel-manager.health-probe.connection")

    init(host: String, port: Int) {
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
    }

    func connect() async throws {
        try Task.checkCancellation()
        let gate = ProbeContinuationGate<Void>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.resume(returning: ())
                    case .failed(let error):
                        gate.resume(throwing: error)
                    case .cancelled:
                        gate.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            gate.resume(throwing: CancellationError())
            connection.cancel()
        }
    }

    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        let gate = ProbeContinuationGate<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        gate.resume(throwing: error)
                    } else {
                        gate.resume(returning: ())
                    }
                })
            }
        } onCancel: {
            gate.resume(throwing: CancellationError())
            connection.cancel()
        }
    }

    func receive(count: Int) async throws -> Data {
        try Task.checkCancellation()
        let gate = ProbeContinuationGate<Data>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                connection.receive(
                    minimumIncompleteLength: count,
                    maximumLength: count
                ) { data, _, isComplete, error in
                    if let error {
                        gate.resume(throwing: error)
                    } else if let data, data.count == count {
                        gate.resume(returning: data)
                    } else if isComplete {
                        gate.resume(throwing: HealthProbeOperationError.connectionClosed)
                    } else {
                        gate.resume(throwing: HealthProbeOperationError.protocolError)
                    }
                }
            }
        } onCancel: {
            gate.resume(throwing: CancellationError())
            connection.cancel()
        }
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

private final class ProbeContinuationGate<Value: Sendable>: @unchecked Sendable {
    private enum State {
        case waiting
        case installed(CheckedContinuation<Value, Error>)
        case completed(Result<Value, Error>)
        case finished
    }

    private let lock = NSLock()
    private var state = State.waiting

    @discardableResult
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        let earlyResult = lock.withLock { () -> Result<Value, Error>? in
            switch state {
            case .waiting:
                state = .installed(continuation)
                return nil
            case .completed(let result):
                state = .finished
                return result
            case .installed, .finished:
                return .failure(CancellationError())
            }
        }
        if let earlyResult {
            continuation.resume(with: earlyResult)
            return false
        }
        return true
    }

    func resume(returning value: Value) {
        finish(.success(value))
    }

    func resume(throwing error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            switch state {
            case .waiting:
                state = .completed(result)
                return nil
            case .installed(let continuation):
                state = .finished
                return continuation
            case .completed, .finished:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}

private final class HTTPHealthProbeOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = ProbeContinuationGate<Int>()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var isFinished = false

    func statusCode(for url: URL, timeout: TimeInterval) async throws -> Int {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = timeout
                let task = session.dataTask(with: request)
                let shouldStart = lock.withLock { () -> Bool in
                    guard !isFinished else { return false }
                    self.session = session
                    self.task = task
                    return true
                }
                guard shouldStart else {
                    task.cancel()
                    session.invalidateAndCancel()
                    return
                }
                task.resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(HealthProbeOperationError.protocolError))
            return
        }
        completionHandler(.cancel)
        finish(.success(response.statusCode))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest redirectedRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.failure(HealthProbeOperationError.protocolError))
        }
    }

    private func finish(_ result: Result<Int, Error>) {
        let values = lock.withLock { () -> (URLSession?, URLSessionDataTask?) in
            guard !isFinished else { return (nil, nil) }
            isFinished = true
            defer {
                session = nil
                task = nil
            }
            return (session, task)
        }
        values.1?.cancel()
        values.0?.invalidateAndCancel()
        switch result {
        case .success(let status):
            gate.resume(returning: status)
        case .failure(let error):
            gate.resume(throwing: error)
        }
    }
}
