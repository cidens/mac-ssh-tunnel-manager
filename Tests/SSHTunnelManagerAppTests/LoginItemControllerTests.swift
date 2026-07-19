import Testing
@testable import SSHTunnelManagerApp

@MainActor
@Test func loginItemControllerRegistersAndUnregistersUsingSystemStatus() {
    let service = StubLoginItemService(status: .notRegistered)
    let controller = LoginItemController(service: service)

    #expect(!controller.isRegistered)
    #expect(controller.setRegistered(true))
    #expect(service.registerCallCount == 1)
    #expect(controller.status == .enabled)
    #expect(controller.isRegistered)

    #expect(controller.setRegistered(false))
    #expect(service.unregisterCallCount == 1)
    #expect(controller.status == .notRegistered)
    #expect(!controller.isRegistered)
}

@MainActor
@Test func loginItemControllerReflectsPendingSystemApprovalAsRegistered() {
    let service = StubLoginItemService(status: .notRegistered)
    service.statusAfterRegister = .requiresApproval
    let controller = LoginItemController(service: service)

    #expect(controller.setRegistered(true))
    #expect(controller.status == .requiresApproval)
    #expect(controller.isRegistered)
}

@MainActor
@Test func loginItemControllerCanRegisterCurrentAppAfterServiceIsNotFound() {
    let service = StubLoginItemService(status: .notFound)
    let controller = LoginItemController(service: service)

    #expect(controller.isSupported)
    #expect(!controller.isRegistered)
    #expect(controller.setRegistered(true))
    #expect(controller.status == .enabled)
    #expect(controller.isRegistered)
}

@MainActor
@Test func loginItemControllerReportsUnsupportedSwiftRunMode() {
    let service = StubLoginItemService(status: .unsupported)
    service.registerError = LoginItemServiceError.unsupportedExecutionMode
    let controller = LoginItemController(service: service)

    #expect(!controller.isSupported)
    #expect(!controller.setRegistered(true))
    #expect(controller.status == .unsupported)
    #expect(!controller.errorMessage.isEmpty)
}

@MainActor
@Test func loginItemControllerPreservesActualStatusWhenRegistrationFails() {
    let service = StubLoginItemService(status: .notRegistered)
    service.registerError = StubLoginItemError.failed
    let controller = LoginItemController(service: service)

    #expect(!controller.setRegistered(true))
    #expect(controller.status == .notRegistered)
    #expect(!controller.errorMessage.isEmpty)
}

private enum StubLoginItemError: Error {
    case failed
}

private final class StubLoginItemService: LoginItemServicing {
    var status: LoginItemRegistrationStatus
    var statusAfterRegister: LoginItemRegistrationStatus = .enabled
    var registerError: Error?
    var unregisterError: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0

    init(status: LoginItemRegistrationStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}
