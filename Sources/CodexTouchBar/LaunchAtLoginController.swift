import CodexTouchBarCore
import Foundation
import OSLog
import ServiceManagement

enum LaunchAtLoginController {
    private static let logger = Logger(
        subsystem: "dev.marlonjd.CodexTouchBar",
        category: "login-item"
    )

    static func registerIfNeeded() {
        let service = SMAppService.mainApp
        let currentState = state(for: service.status)
        logger.info("Login item status: \(currentState.description, privacy: .public)")
        guard LaunchAtLoginPolicy.shouldRegister(currentState: currentState) else {
            return
        }

        do {
            try service.register()
            logger.info("Login item registration requested successfully")
        } catch {
            logger.error("Could not register login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    static var statusDescription: String {
        state(for: SMAppService.mainApp.status).description
    }

    private static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

private extension LaunchAtLoginState {
    var description: String {
        switch self {
        case .notRegistered:
            return "notRegistered"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .unavailable:
            return "notFound"
        }
    }
}
