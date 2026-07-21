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
    let groups = grouper.groups(from: threads)

    #expect(groups.map(\.name) == ["AviaSurveil360", "Unnamed Project"])
    #expect(groups[0].threads.map(\.id) == ["avia-1", "avia-2"])
    #expect(groups[1].isUnnamed)
}

private func makeThread(id: String, cwd: URL, startedAt: TimeInterval) -> ActiveThread {
    ActiveThread(
        id: id,
        cwd: cwd,
        startedAt: Date(timeIntervalSince1970: startedAt),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
}
