import CodexTouchBarCore
import Testing

@Test func parsesAnEffortAccessibilityDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-effort", "xhigh"])

    #expect(command == .diagnoseEffort("xhigh"))
}

@Test func keepsTheExistingRolloutDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose"])

    #expect(command == .diagnoseRollouts)
}

@Test func parsesAnAccessibilityTreeDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-accessibility-tree"])

    #expect(command == .diagnoseAccessibilityTree)
}

@Test func parsesAnAccessibilityPIDDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-accessibility-pid", "6498"])

    #expect(command == .diagnoseAccessibilityPID(6498))
}

@Test func parsesALoginItemStatusDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--login-item-status"])

    #expect(command == .diagnoseLoginItem)
}
