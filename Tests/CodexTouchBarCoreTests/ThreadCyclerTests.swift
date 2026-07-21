import CodexTouchBarCore
import Foundation
import Testing

@Test func cyclesThroughThreadsAndWrapsToTheFirstThread() throws {
    let first = ActiveThread(
        id: "first",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 3)
    )
    let second = ActiveThread(
        id: "second",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(timeIntervalSince1970: 2),
        updatedAt: Date(timeIntervalSince1970: 3)
    )
    let group = ProjectGroup(id: "project", name: "Project", threads: [first, second], isUnnamed: false)
    var cycler = ThreadCycler()

    #expect(cycler.nextThread(in: group)?.id == "first")
    #expect(cycler.nextThread(in: group)?.id == "second")
    #expect(cycler.nextThread(in: group)?.id == "first")
}

@Test func truncatesLongProjectNames() {
    let group = ProjectGroup(
        id: "long",
        name: "flutter_desktop_updater_project",
        threads: [],
        isUnnamed: false
    )

    #expect(group.displayName(maxLength: 12) == "flutter_des…")
    #expect(group.displayName(maxLength: 40) == "flutter_desktop_updater_project")
}
