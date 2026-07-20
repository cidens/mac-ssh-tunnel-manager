import Foundation
import Network
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@Test func systemHealthProberChecksTCPListenersAndConnectionRefusal() async throws {
    let server = try LocalHealthTestServer { connection, queue in
        connection.start(queue: queue)
    }
    defer { server.cancel() }
    let prober = SystemHealthProber()

    let success = await prober.probe(healthProbeRequest(
        port: server.port,
        configuration: TunnelHealthCheckConfiguration(kind: .tcp, timeout: 1)
    ))
    #expect(success == .success)

    let refused = await prober.probe(healthProbeRequest(
        port: 1,
        configuration: TunnelHealthCheckConfiguration(kind: .tcp, timeout: 1)
    ))
    #expect(refused == .failure(.connectionRefused) || refused == .failure(.timeout))
    #expect(SystemHealthProber.category(for: NWError.posix(.ECONNREFUSED)) == .connectionRefused)
    #expect(SystemHealthProber.category(for: URLError(.cannotConnectToHost)) == .connectionRefused)
}

@Test func systemHealthProberPerformsExactSOCKS5Greeting() async throws {
    let greeting = LockedValue(Data())
    let server = try LocalHealthTestServer { connection, queue in
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.receive(minimumIncompleteLength: 3, maximumLength: 3) { data, _, _, _ in
                greeting.set(data ?? Data())
                connection.send(content: Data([0x05, 0x00]), completion: .contentProcessed { _ in })
            }
        }
        connection.start(queue: queue)
    }
    defer { server.cancel() }

    let result = await SystemHealthProber().probe(healthProbeRequest(
        port: server.port,
        configuration: TunnelHealthCheckConfiguration(kind: .socks5, timeout: 1)
    ))

    #expect(result == .success)
    #expect(greeting.value == Data([0x05, 0x01, 0x00]))
}

@Test func systemHealthProberRejectsSOCKS5AuthenticationAndMalformedResponses() async throws {
    for (response, expected) in [
        (Data([0x05, 0x02]), HealthProbeResult.failure(.authenticationRequired)),
        (Data([0x04, 0x00]), HealthProbeResult.failure(.protocolError)),
    ] {
        let server = try LocalHealthTestServer { connection, queue in
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.receive(minimumIncompleteLength: 3, maximumLength: 3) { _, _, _, _ in
                    connection.send(content: response, completion: .contentProcessed { _ in })
                }
            }
            connection.start(queue: queue)
        }
        let result = await SystemHealthProber().probe(healthProbeRequest(
            port: server.port,
            configuration: TunnelHealthCheckConfiguration(kind: .socks5, timeout: 1)
        ))
        server.cancel()
        #expect(result == expected)
    }
}

@Test func systemHealthProberUsesHTTPHeadersWithoutRetainingOrWaitingForBody() async throws {
    let server = try httpHealthTestServer(status: 204, declaredBodyBytes: 50_000_000)
    defer { server.cancel() }
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/health?ready=1"))
    let started = ContinuousClock.now

    let result = await SystemHealthProber().probe(healthProbeRequest(
        port: server.port,
        configuration: TunnelHealthCheckConfiguration(kind: .http, url: url, timeout: 2)
    ))

    #expect(result == .success)
    #expect(ContinuousClock.now - started < .seconds(1))
}

@Test func systemHealthProberReportsUnexpectedHTTPStatus() async throws {
    let server = try httpHealthTestServer(status: 503, declaredBodyBytes: 0)
    defer { server.cancel() }
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/health"))

    let result = await SystemHealthProber().probe(healthProbeRequest(
        port: server.port,
        configuration: TunnelHealthCheckConfiguration(kind: .http, url: url, timeout: 1)
    ))

    #expect(result == .failure(.httpStatus))
}

@Test func systemHealthProberAcceptsHTTPRedirectStatusWithoutFollowingIt() async throws {
    let server = try httpHealthTestServer(status: 302, declaredBodyBytes: 0)
    defer { server.cancel() }
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/health"))

    let result = await SystemHealthProber().probe(healthProbeRequest(
        port: server.port,
        configuration: TunnelHealthCheckConfiguration(kind: .http, url: url, timeout: 1)
    ))

    #expect(result == .success)
}

@Test func cancellingAHealthProbeReleasesThePendingNetworkOperation() async throws {
    let server = try LocalHealthTestServer { connection, queue in
        connection.start(queue: queue)
    }
    defer { server.cancel() }
    let task = Task {
        await SystemHealthProber().probe(healthProbeRequest(
            port: server.port,
            configuration: TunnelHealthCheckConfiguration(kind: .socks5, timeout: 10)
        ))
    }
    try await Task.sleep(for: .milliseconds(50))
    let started = ContinuousClock.now

    task.cancel()
    let result = await task.value

    #expect(result == .failure(.cancelled))
    #expect(ContinuousClock.now - started < .seconds(1))
}

@Test func immediatelyCancelledProbesDoNotLoseTheirContinuations() async {
    let request = healthProbeRequest(
        port: 1,
        configuration: TunnelHealthCheckConfiguration(kind: .tcp, timeout: 10)
    )
    for _ in 0..<100 {
        let task = Task { await SystemHealthProber().probe(request) }
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
    }
}

@Test func wildcardHealthProbeHostsUseLoopbackConnections() {
    let configuration = TunnelHealthCheckConfiguration(kind: .tcp)
    #expect(healthProbeRequest(host: "0.0.0.0", port: 1, configuration: configuration).connectionHost == "127.0.0.1")
    #expect(healthProbeRequest(host: "*", port: 1, configuration: configuration).connectionHost == "127.0.0.1")
    #expect(healthProbeRequest(host: "[::]", port: 1, configuration: configuration).connectionHost == "::1")
    #expect(healthProbeRequest(host: "[::1]", port: 1, configuration: configuration).connectionHost == "::1")
}

private func healthProbeRequest(
    host: String = "127.0.0.1",
    port: Int,
    configuration: TunnelHealthCheckConfiguration
) -> HealthProbeRequest {
    HealthProbeRequest(
        key: RuleHealthCheckKey(tunnelID: UUID(), ruleID: UUID()),
        generation: 1,
        listenerHost: host,
        listenerPort: port,
        configuration: configuration
    )
}

private func httpHealthTestServer(
    status: Int,
    declaredBodyBytes: Int
) throws -> LocalHealthTestServer {
    try LocalHealthTestServer { connection, queue in
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { _, _, _, _ in
                let redirectHeader = (300...399).contains(status) ? "Location: /redirected\r\n" : ""
                let response = "HTTP/1.1 \(status) Test\r\n\(redirectHeader)Content-Length: \(declaredBodyBytes)\r\nConnection: keep-alive\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            }
        }
        connection.start(queue: queue)
    }
}

private final class LocalHealthTestServer: @unchecked Sendable {
    typealias ConnectionHandler = @Sendable (NWConnection, DispatchQueue) -> Void

    private let listener: NWListener
    private let queue = DispatchQueue(label: "ssh-tunnel-manager.tests.health-server")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private(set) var port = 0

    init(handler: @escaping ConnectionHandler) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        let failed = LockedValue<NWError?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                failed.set(error)
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.lock.withLock { self.connections.append(connection) }
            handler(connection, self.queue)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success else {
            listener.cancel()
            throw LocalHealthTestServerError.startTimedOut
        }
        if let error = failed.value {
            listener.cancel()
            throw error
        }
        guard let listenerPort = listener.port else {
            listener.cancel()
            throw LocalHealthTestServerError.missingPort
        }
        port = Int(listenerPort.rawValue)
    }

    func cancel() {
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
        listener.cancel()
        let retained = lock.withLock { () -> [NWConnection] in
            defer { connections.removeAll() }
            return connections
        }
        for connection in retained {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }

    deinit {
        cancel()
    }
}

private enum LocalHealthTestServerError: Error {
    case startTimedOut
    case missingPort
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }
}
