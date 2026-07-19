import Foundation
import ServiceManagement

enum LoginItemRegistrationStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unsupported
}

enum LoginItemServiceError: Error, Equatable {
    case unsupportedExecutionMode
}

protocol LoginItemServicing {
    var status: LoginItemRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItemService: LoginItemServicing {
    private var isPackagedApplication: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    var status: LoginItemRegistrationStatus {
        guard isPackagedApplication else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        guard isPackagedApplication else {
            throw LoginItemServiceError.unsupportedExecutionMode
        }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard isPackagedApplication else {
            throw LoginItemServiceError.unsupportedExecutionMode
        }
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: LoginItemRegistrationStatus
    @Published private(set) var errorMessage = ""

    private let service: any LoginItemServicing

    init(service: any LoginItemServicing = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var isSupported: Bool {
        status != .unsupported
    }

    func refresh() {
        status = service.status
        errorMessage = ""
    }

    @discardableResult
    func setRegistered(_ shouldRegister: Bool) -> Bool {
        errorMessage = ""
        do {
            if shouldRegister {
                try service.register()
            } else {
                try service.unregister()
            }
            status = service.status
            return true
        } catch LoginItemServiceError.unsupportedExecutionMode {
            status = .unsupported
            errorMessage = AppStrings.loginItemUnsupported()
            return false
        } catch {
            status = service.status
            errorMessage = AppStrings.loginItemOperationFailed(error.localizedDescription)
            return false
        }
    }
}
