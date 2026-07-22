public enum LaunchAtLoginState: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public enum LaunchAtLoginPolicy {
    public static func shouldRegister(currentState: LaunchAtLoginState) -> Bool {
        switch currentState {
        case .notRegistered, .unavailable:
            return true
        case .enabled, .requiresApproval:
            return false
        }
    }
}
