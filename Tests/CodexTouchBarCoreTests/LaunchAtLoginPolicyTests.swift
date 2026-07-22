import CodexTouchBarCore
import Testing

@Test func launchAtLoginRegistersFromMissingRegistrationStates() {
    #expect(LaunchAtLoginPolicy.shouldRegister(currentState: .notRegistered))
    #expect(!LaunchAtLoginPolicy.shouldRegister(currentState: .enabled))
    #expect(!LaunchAtLoginPolicy.shouldRegister(currentState: .requiresApproval))
    #expect(LaunchAtLoginPolicy.shouldRegister(currentState: .unavailable))
}
