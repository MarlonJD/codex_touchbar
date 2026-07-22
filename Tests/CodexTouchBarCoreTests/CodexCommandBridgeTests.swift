import CodexTouchBarCore
import Foundation
import Testing

@Test func mergesPrivateCommandBindingsWithoutDroppingUserBindings() throws {
    let existing = """
    [
      {"command":"newTask","key":"Cmd+N"},
      {"command":"composer.increaseReasoningEffort","key":"Cmd+Shift+I"}
    ]
    """.data(using: .utf8)!

    let merged = try CodexCommandKeymap.mergingPrivateBindings(into: existing)
    let bindings = try JSONDecoder().decode([CodexKeyBinding].self, from: merged)

    #expect(bindings.contains(CodexKeyBinding(command: "newTask", key: "Cmd+N")))
    #expect(bindings.contains(CodexKeyBinding(command: "composer.increaseReasoningEffort", key: "Cmd+Shift+I")))
    #expect(bindings.contains(CodexCommandKeymap.increaseEffortBinding))
    #expect(bindings.contains(CodexCommandKeymap.decreaseEffortBinding))
    #expect(bindings.contains(CodexCommandKeymap.toggleFastModeBinding))
}

@Test func mergingPrivateCommandBindingsIsIdempotent() throws {
    let first = try CodexCommandKeymap.mergingPrivateBindings(into: nil)
    let second = try CodexCommandKeymap.mergingPrivateBindings(into: first)

    #expect(first == second)
}

@Test func effortCommandPlanIncludesTheMaximumStepWhenMovingToUltra() {
    let plan = CodexCommandPlan.effort(targetIndex: 5, optionCount: 6)

    #expect(plan == Array(repeating: .decreaseEffort, count: 6)
        + Array(repeating: .increaseEffort, count: 5))
}

@Test func effortCommandPlanRejectsInvalidTargets() {
    #expect(CodexCommandPlan.effort(targetIndex: -1, optionCount: 5).isEmpty)
    #expect(CodexCommandPlan.effort(targetIndex: 5, optionCount: 5).isEmpty)
    #expect(CodexCommandPlan.effort(targetIndex: 0, optionCount: 0).isEmpty)
}

@Test func commandBridgeRequiresRestartWhenKeymapChangedAfterCodexLaunched() {
    let launchDate = Date(timeIntervalSince1970: 100)
    let keymapDate = Date(timeIntervalSince1970: 101)

    #expect(CodexCommandBridgeRuntime.requiresRestart(
        codexLaunchDate: launchDate,
        keymapModificationDate: keymapDate
    ))
}

@Test func commandBridgeIsReadyWhenCodexLaunchedAfterKeymapWasWritten() {
    let keymapDate = Date(timeIntervalSince1970: 100)
    let launchDate = Date(timeIntervalSince1970: 101)

    #expect(!CodexCommandBridgeRuntime.requiresRestart(
        codexLaunchDate: launchDate,
        keymapModificationDate: keymapDate
    ))
}
