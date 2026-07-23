@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func refreshPolicyPollsOnlyWhileCodexIsFrontmost() {
    #expect(RefreshPolicy.pollInterval(codexIsFrontmost: false) == nil)
    #expect(RefreshPolicy.pollInterval(codexIsFrontmost: true) == 1)
}

@Test func refreshTimerRunsDuringTouchBarEventTracking() {
    #expect(RefreshPolicy.timerRunLoopMode == .common)
}

@Test func refreshPolicySkipsAnUnchangedTouchBarModel() {
    let thread = ActiveThread(
        id: "thread",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2)
    )
    let groups = [ProjectGroup(
        id: "/tmp/project",
        name: "project",
        threads: [thread],
        isUnnamed: false
    )]

    #expect(RefreshPolicy.shouldApply(previous: nil, next: groups))
    #expect(!RefreshPolicy.shouldApply(previous: groups, next: groups))
}
