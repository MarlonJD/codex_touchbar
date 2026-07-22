import CSQLite
@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func reportsOnlyRolloutsWhoseLatestTaskEventIsStarted() async throws {
    let sessionsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: sessionsRoot) }
    try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)

    try rollout(
        id: "active-thread",
        cwd: "/tmp/active",
        events: ["task_started"],
        at: sessionsRoot.appendingPathComponent("active.jsonl")
    )
    try rollout(
        id: "complete-thread",
        cwd: "/tmp/complete",
        events: ["task_started", "task_complete"],
        at: sessionsRoot.appendingPathComponent("complete.jsonl")
    )
    try rollout(
        id: "aborted-thread",
        cwd: "/tmp/aborted",
        events: ["task_started", "turn_aborted"],
        at: sessionsRoot.appendingPathComponent("aborted.jsonl")
    )
    try rollout(
        id: "internal-subagent",
        cwd: "/tmp/active",
        threadSource: "subagent",
        events: ["task_started"],
        at: sessionsRoot.appendingPathComponent("subagent.jsonl")
    )

    let scanner = RolloutScanner(sessionsRoot: sessionsRoot, stateDatabase: nil, recentFileInterval: 60)
    let threads = await scanner.scan()

    #expect(threads.map(\.id) == ["active-thread"])
    #expect(threads.first?.cwd.path == "/tmp/active")
}

@Test func reportsVisibleRootWhenItsDelegatedTaskIsActive() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let rootRollout = root.appendingPathComponent("root.jsonl")
    let childRollout = root.appendingPathComponent("child.jsonl")
    try rollout(
        id: "visible-root",
        cwd: "/tmp/visible-project",
        events: ["task_started", "task_complete"],
        at: rootRollout
    )
    try rollout(
        id: "delegated-child",
        cwd: "/tmp/visible-project",
        threadSource: "subagent",
        events: ["task_started"],
        at: childRollout
    )

    let databaseURL = root.appendingPathComponent("state.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    guard let database else {
        return
    }
    defer { sqlite3_close(database) }

    let updatedAt = Int64(Date().addingTimeInterval(-120).timeIntervalSince1970)
    let childUpdatedAt = Int64(Date().addingTimeInterval(-10).timeIntervalSince1970)
    let sql = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      cwd TEXT NOT NULL,
      rollout_path TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      recency_at_ms INTEGER NOT NULL,
      archived INTEGER NOT NULL
    );
    CREATE TABLE thread_spawn_edges (
      parent_thread_id TEXT NOT NULL,
      child_thread_id TEXT NOT NULL
    );
    INSERT INTO threads VALUES (
      'visible-root', '/tmp/visible-project', '\(rootRollout.path)',
      \(updatedAt), \(updatedAt * 1_000), 0
    );
    INSERT INTO threads VALUES (
      'delegated-child', '/tmp/visible-project', '\(childRollout.path)',
      \(childUpdatedAt), \(childUpdatedAt * 1_000), 0
    );
    INSERT INTO thread_spawn_edges VALUES ('visible-root', 'delegated-child');
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: databaseURL,
        recentFileInterval: 60
    )
    let threads = await scanner.scan()

    #expect(threads.map(\.id) == ["visible-root"])
    #expect(threads.first?.cwd.path == "/tmp/visible-project")
    #expect(Int64(threads.first?.updatedAt.timeIntervalSince1970 ?? 0) == updatedAt)
    #expect(Int64(threads.first?.projectRecencyAt.timeIntervalSince1970 ?? 0) == childUpdatedAt)
}

private func rollout(
    id: String,
    cwd: String,
    threadSource: String = "user",
    events: [String],
    at url: URL
) throws {
    var lines = [
        "{\"timestamp\":\"2026-07-21T01:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\",\"thread_source\":\"\(threadSource)\"}}",
    ]
    lines.append(contentsOf: events.enumerated().map { index, event in
        "{\"timestamp\":\"2026-07-21T01:00:0\(index + 1).000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\"}}"
    })
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

@Test func tailReaderProcessesOnlyBytesAppendedAfterTheCursor() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }

    let initial = String(repeating: "{\"type\":\"response_item\"}\n", count: 20_000)
    try initial.write(to: url, atomically: true, encoding: .utf8)
    let initialSize = UInt64(initial.utf8.count)
    let appended = """
    {"type":"response_item"}
    {"timestamp":"2026-07-21T01:00:02.000Z","type":"event_msg","payload":{"type":"task_complete"}}

    """
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(appended.utf8))
    try handle.close()

    let update = try RolloutTailReader.readChanges(at: url, from: initialSize)

    #expect(update.bytesRead == appended.utf8.count)
    #expect(update.processedOffset == initialSize + UInt64(appended.utf8.count))
    #expect(update.latestEvent?.type == "task_complete")
}

@Test func tailReaderRetriesAnIncompleteFinalLine() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }

    let firstHalf = "{\"timestamp\":\"2026-07-21T01:00:02.000Z\",\"type\":\"event_msg\","
    try firstHalf.write(to: url, atomically: true, encoding: .utf8)

    let incomplete = try RolloutTailReader.readChanges(at: url, from: 0)
    #expect(incomplete.processedOffset == 0)
    #expect(incomplete.latestEvent == nil)

    let secondHalf = "\"payload\":{\"type\":\"task_started\"}}\n"
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(secondHalf.utf8))
    try handle.close()

    let complete = try RolloutTailReader.readChanges(at: url, from: incomplete.processedOffset)
    #expect(complete.processedOffset == UInt64(firstHalf.utf8.count + secondHalf.utf8.count))
    #expect(complete.latestEvent?.type == "task_started")
}
