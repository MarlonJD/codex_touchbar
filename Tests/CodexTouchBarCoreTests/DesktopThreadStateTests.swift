import Foundation
import Testing
@testable import CodexTouchBarCore

private func snapshot(
    _ identity: DesktopThreadIdentity,
    status: String = "active",
    unread: Bool = false,
    revision: Int = 1
) -> [String: Any] {
    ["type": "snapshot", "revision": revision, "conversationState": [
        "id": identity.threadID, "hostId": identity.hostID,
        "title": "A task", "cwd": "/repo/project", "createdAt": 1_790_000_000_000,
        "updatedAt": 1_790_000_030_000, "recencyAt": 1_790_000_040_000,
        "threadRuntimeStatus": ["type": status], "hasUnreadTurn": unread,
        "latestModel": "gpt-6-astra", "latestReasoningEffort": "max",
        "latestThreadSettings": ["serviceTier": "default", "developer_instructions": "ignored"],
        "turnHistory": ["history": ["content": "never retained"]],
    ]]
}

@Test func discoversLocalRemoteAndCloudThreadsWithoutLocalRollouts() {
    var state = DesktopThreadState()
    let identities = ["local", "remote-control:mac-mini", "durable"].map {
        DesktopThreadIdentity(hostID: $0, threadID: "same-id")
    }
    for identity in identities {
        let received = state.receive(identity: identity, owner: identity.hostID, change: snapshot(identity))
        #expect(received)
    }
    #expect(Set(state.threads().map(\.identity)) == Set(identities))
    let groups = ProjectGrouper().groups(from: state.threads())
    #expect(groups.count == 3)
    #expect(groups.first { $0.hostID == "durable" }?.name == "Bulut")
    #expect(groups.first { $0.hostID == "remote-control:mac-mini" }?.symbolName == "desktopcomputer")
    #expect(state.settings(for: identities[0])?.modelAndEffortTitle == "GPT-6 Astra Max")
    #expect(state.threads().first?.updatedAt == Date(timeIntervalSince1970: 1_790_000_030))
}

@Test func completionOverridesStaleLocalRolloutAndKeepsUnreadResult() {
    var state = DesktopThreadState()
    let identity = DesktopThreadIdentity(hostID: "local", threadID: "task")
    state.receive(identity: identity, owner: "desktop", change: snapshot(identity))
    let staleLocal = state.threads()
    let completed = state.receive(identity: identity, owner: "desktop", change: [
        "type": "patches", "baseRevision": 1, "revision": 2,
        "patches": [
            ["op": "replace", "path": ["threadRuntimeStatus", "type"], "value": "idle"],
            ["op": "replace", "path": ["hasUnreadTurn"], "value": true],
            ["op": "add", "path": ["turnHistory", "history", "content"], "value": "ignored"],
        ],
    ])
    #expect(completed)
    let merged = state.merging(localThreads: staleLocal)
    #expect(merged.count == 1)
    #expect(merged.first?.isActive == false)
    #expect(merged.first?.isUnread == true)
    state.receive(identity: identity, owner: "desktop", change: [
        "type": "patches", "baseRevision": 2, "revision": 3,
        "patches": [["op": "replace", "path": ["hasUnreadTurn"], "value": false]],
    ])
    #expect(state.merging(localThreads: staleLocal).isEmpty)
}

@Test func streamGapAndOwnerDisconnectInvalidateUnverifiableTaskState() {
    var state = DesktopThreadState()
    let remote = DesktopThreadIdentity(hostID: "remote", threadID: "task")
    let cloud = DesktopThreadIdentity(hostID: "durable", threadID: "task")
    state.receive(identity: remote, owner: "mac-mini", change: snapshot(remote))
    state.receive(identity: cloud, owner: "cloud-owner", change: snapshot(cloud))
    let received = state.receive(identity: remote, owner: "mac-mini", change: [
        "type": "patches", "baseRevision": 10, "revision": 11, "patches": [],
    ])
    #expect(!received)
    #expect(state.identities == [cloud])
    state.removeOwner("cloud-owner")
    #expect(state.threads().isEmpty)
}

@Test func readingACompletedTaskClearsTheDotWithoutStartingAnotherTurn() {
    var state = DesktopThreadState()
    let first = DesktopThreadIdentity(hostID: "local", threadID: "first")
    let second = DesktopThreadIdentity(hostID: "local", threadID: "second")
    state.receive(identity: first, owner: "desktop", change: snapshot(first, status: "idle", unread: true))
    state.receive(identity: second, owner: "desktop", change: snapshot(second, status: "idle", unread: true))
    #expect(ProjectGrouper().groups(from: state.threads()).first?.hasUnread == true)

    state.updateReadState(for: first, hasUnreadTurn: false)
    #expect(state.threads().map(\.id) == ["second"])
    #expect(ProjectGrouper().groups(from: state.threads()).first?.hasUnread == true)

    state.updateReadState(for: second, hasUnreadTurn: false)
    #expect(state.threads().isEmpty)
    let selectedGroups = ProjectGrouper().groups(
        from: state.threads(),
        selectedProjectRoots: [URL(fileURLWithPath: "/repo/project")]
    )
    #expect(selectedGroups.count == 1)
    #expect(selectedGroups.first?.isSelected == true)
    #expect(selectedGroups.first?.hasUnread == false)

    // A task snapshot can still carry its old unread flag after the independent read receipt.
    state.receive(identity: first, owner: "desktop", change: snapshot(first, status: "idle", unread: true, revision: 2))
    #expect(state.threads().isEmpty)

    // A newly completed result or an explicit mark-unread event restores the indicator.
    state.updateReadState(for: first, hasUnreadTurn: true)
    #expect(state.threads().map(\.id) == ["first"])
}

@Test func readReceiptsBeforeSnapshotsAreScopedToTheirHostAndResetOnDisconnect() {
    var state = DesktopThreadState()
    let local = DesktopThreadIdentity(hostID: "local", threadID: "task")
    let remote = DesktopThreadIdentity(hostID: "remote", threadID: "task")
    state.updateReadState(for: local, hasUnreadTurn: false)
    state.receive(identity: local, owner: "desktop", change: snapshot(local, status: "idle", unread: true))
    state.receive(identity: remote, owner: "remote-owner", change: snapshot(remote, status: "idle", unread: true))
    #expect(state.threads().map(\.identity) == [remote])
    state.removeOwner("desktop")
    state.receive(identity: local, owner: "new-owner", change: snapshot(local, status: "idle", unread: true))
    #expect(Set(state.threads().map(\.identity)) == [local, remote])
    state.reset()
    state.receive(identity: local, owner: "new-owner", change: snapshot(local, status: "idle", unread: true))
    #expect(state.threads().map(\.identity) == [local])
}

@Test func settingsTrackPatchesAndAmbiguousTaskTitlesAreNotGuessed() {
    var state = DesktopThreadState()
    let local = DesktopThreadIdentity(hostID: "local", threadID: "task")
    let remote = DesktopThreadIdentity(hostID: "remote", threadID: "task")
    state.receive(identity: local, owner: "desktop", change: snapshot(local))
    #expect(state.identity(matchingSelectedLabel: "A task") == local)
    state.receive(identity: local, owner: "desktop", change: [
        "type": "patches", "baseRevision": 1, "revision": 2,
        "patches": [["op": "replace", "path": ["latestThreadSettings", "serviceTier"], "value": "priority"]],
    ])
    #expect(state.settings(for: local)?.serviceTier == "priority")
    state.receive(identity: remote, owner: "remote", change: snapshot(remote))
    #expect(state.identity(matchingSelectedLabel: "A task") == nil)
}

@Test func keepsSelectedRemoteProjectSeparateFromIdenticalLocalPath() {
    var state = DesktopThreadState()
    let local = DesktopThreadIdentity(hostID: "local", threadID: "task")
    let remote = DesktopThreadIdentity(hostID: "remote", threadID: "task")
    state.receive(identity: local, owner: "desktop", change: snapshot(local))
    state.receive(identity: remote, owner: "desktop", change: snapshot(remote))
    let groups = ProjectGrouper().groups(from: state.threads(), selectedThreadIdentity: remote)
    #expect(groups.first?.hostID == "remote")
    #expect(groups.first?.isSelected == true)
    #expect(groups.last?.isSelected == false)
    let url = state.threads().first { $0.hostID == "remote" }?.navigationURL
    #expect(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "remote")
}

@Test func decodesFragmentedAndCoalescedDesktopFramesWithoutSplittingUnicode() throws {
    let first = Data("{\"title\":\"Türkçe\"}".utf8)
    let second = Data("{}".utf8)
    let frames = DesktopIPCFrameDecoder.encode(first) + DesktopIPCFrameDecoder.encode(second)
    var decoder = DesktopIPCFrameDecoder()
    #expect(try decoder.append(frames.prefix(2)).isEmpty)
    #expect(try decoder.append(frames.dropFirst(2).prefix(8)).isEmpty)
    #expect(try decoder.append(frames.dropFirst(10)) == [first, second])
    #expect(throws: DesktopIPCFrameDecoder.FrameError.self) {
        try decoder.append(Data([255, 255, 255, 255]))
    }
}

@Test func selectedComposerLabelsAndMissingContextDoNotUseGlobalDefaults() {
    let settings = ComposerSettings(model: "gpt-6-astra", effort: "max", serviceTier: "default")
    #expect(ComposerDisplayState().resolving(settings: settings) == .init(modelTitle: "GPT-6 Astra Max", speedTitle: "1x"))
    #expect(ComposerDisplayState().resolving(settings: nil) == .init())
    let names = ["gpt-6-astra", "GPT-6-Sol"]
    let visible = ComposerDisplayState.fromControlLabels(["GPT-6 Sol High", "2×"], modelNames: names)
    #expect(visible.resolving(settings: settings) == .init(modelTitle: "GPT-6 Sol High", speedTitle: "2x"))
    let compact = ComposerDisplayState.fromControlLabels(["6 Astra Max"], modelNames: names)
    #expect(compact.resolving(settings: settings) == .init(modelTitle: "6 Astra Max", speedTitle: "1x"))
    #expect(ComposerDisplayState.fromControlLabels(["GPT‑6 Astra Max"], modelNames: names).modelTitle == "GPT‑6 Astra Max")
    #expect(ComposerDisplayState.fromControlLabels(["Choose GPT-6 Astra for this task"], modelNames: names).modelTitle == nil)
}

@Test func messageNavigationControlsCannotOverrideTheSelectedModel() {
    let settings = ComposerSettings(model: "gpt-6-astra", effort: "max", serviceTier: "default")
    let labels = ["3 numaralı kullanıcı mesajına git", "6 messages", "GPT-6 Astra is a model"]
    let display = ComposerDisplayState.fromControlLabels(labels, modelNames: ["GPT-6-Astra"])
    #expect(display.modelTitle == nil)
    #expect(display.resolving(settings: settings) == .init(modelTitle: "GPT-6 Astra Max", speedTitle: "1x"))
    #expect(ComposerDisplayState.fromControlLabels(["6 Astra Max"], modelNames: []).modelTitle == nil)
}
