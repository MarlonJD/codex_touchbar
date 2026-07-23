import CodexTouchBarCore
import Foundation
import Testing

@Test func groupsRepositoryThreadsAndPlacesUnnamedProjectLast() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let scratchRoot = root.appendingPathComponent("Documents/Codex", isDirectory: true)
    let unnamedDirectory = scratchRoot.appendingPathComponent("2026-07-21/session", isDirectory: true)
    let repositoryRoot = root.appendingPathComponent("AviaSurveil360", isDirectory: true)
    let repositoryChild = repositoryRoot.appendingPathComponent("Sources/App", isDirectory: true)
    try FileManager.default.createDirectory(at: unnamedDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: repositoryChild, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: repositoryRoot.appendingPathComponent(".git", isDirectory: true),
        withIntermediateDirectories: true
    )

    let threads = [
        makeThread(id: "avia-2", cwd: repositoryChild, startedAt: 2),
        makeThread(id: "unnamed", cwd: unnamedDirectory, startedAt: 3),
        makeThread(id: "avia-1", cwd: repositoryRoot, startedAt: 1),
    ]
    let grouper = ProjectGrouper(scratchRoot: scratchRoot, homeDirectory: root)
    let groups = grouper.groups(
        from: threads,
        unreadWorkingDirectories: [repositoryChild]
    )

    #expect(groups.map(\.name) == ["AviaSurveil360", "Unnamed Project"])
    #expect(groups[0].threads.map(\.id) == ["avia-1", "avia-2"])
    #expect(groups[0].hasUnread)
    #expect(!groups[1].hasUnread)
    #expect(groups[1].isUnnamed)
}

@Test func ordersProjectGroupsByCodexProjectRecency() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let oldest = root.appendingPathComponent("aviaSurveil360", isDirectory: true)
    let newest = root.appendingPathComponent("flutter_desktop_updater", isDirectory: true)
    let middle = root.appendingPathComponent("flutter_scene_viewer", isDirectory: true)
    for repository in [oldest, newest, middle] {
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    let threads = [
        makeThread(
            id: "avia",
            cwd: oldest,
            startedAt: 1,
            updatedAt: 30,
            projectRecencyAt: 10
        ),
        makeThread(
            id: "desktop",
            cwd: newest,
            startedAt: 2,
            updatedAt: 10,
            projectRecencyAt: 30
        ),
        makeThread(
            id: "scene",
            cwd: middle,
            startedAt: 3,
            updatedAt: 20,
            projectRecencyAt: 20
        ),
    ]
    let grouper = ProjectGrouper(
        scratchRoot: root.appendingPathComponent("scratch", isDirectory: true),
        homeDirectory: root
    )

    #expect(
        grouper.groups(from: threads).map(\.name)
            == ["flutter_desktop_updater", "flutter_scene_viewer", "aviaSurveil360"]
    )
}

private func makeThread(
    id: String,
    cwd: URL,
    startedAt: TimeInterval,
    updatedAt: TimeInterval = 10,
    projectRecencyAt: TimeInterval? = nil
) -> ActiveThread {
    ActiveThread(
        id: id,
        cwd: cwd,
        startedAt: Date(timeIntervalSince1970: startedAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        projectRecencyAt: projectRecencyAt.map(Date.init(timeIntervalSince1970:))
    )
}
