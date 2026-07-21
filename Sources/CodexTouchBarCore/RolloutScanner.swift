import CSQLite
import Foundation

public actor RolloutScanner {
    private struct CachedRollout {
        let modificationDate: Date
        let fileSize: Int
        let allowsSubagent: Bool
        let record: RolloutRecord?
    }

    private struct RolloutRecord {
        let thread: ActiveThread
        let isActive: Bool
    }

    private struct IndexedThreadRoot {
        let id: String
        let cwd: URL
        var rolloutURLs: [URL]
    }

    private let sessionsRoot: URL
    private let stateDatabase: URL?
    private let recentFileInterval: TimeInterval
    private var cache: [URL: CachedRollout] = [:]

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        stateDatabase: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        recentFileInterval: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.sessionsRoot = sessionsRoot
        self.stateDatabase = stateDatabase
        self.recentFileInterval = recentFileInterval
    }

    public func scan() -> [ActiveThread] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        let cutoff = Date().addingTimeInterval(-recentFileInterval)
        var seenURLs = Set<URL>()
        let activeThreads: [ActiveThread]

        if let indexedRoots = indexedThreadRoots() {
            activeThreads = indexedRoots.compactMap { root in
                let activeRecords = root.rolloutURLs.compactMap { url in
                    cachedRecord(
                        at: url,
                        allowsSubagent: true,
                        cutoff: cutoff,
                        resourceKeys: resourceKeys,
                        seenURLs: &seenURLs
                    )
                }
                .filter(\.isActive)

                guard let startedAt = activeRecords.map(\.thread.startedAt).min(),
                      let updatedAt = activeRecords.map(\.thread.updatedAt).max() else {
                    return nil
                }
                return ActiveThread(id: root.id, cwd: root.cwd, startedAt: startedAt, updatedAt: updatedAt)
            }
        } else {
            var activeThreadsByID: [String: ActiveThread] = [:]
            for url in fallbackRolloutURLs(fileManager: fileManager, resourceKeys: resourceKeys) {
                guard let record = cachedRecord(
                    at: url,
                    allowsSubagent: false,
                    cutoff: cutoff,
                    resourceKeys: resourceKeys,
                    seenURLs: &seenURLs
                ), record.isActive else {
                    continue
                }
                let existing = activeThreadsByID[record.thread.id]
                if existing == nil || record.thread.updatedAt > existing!.updatedAt {
                    activeThreadsByID[record.thread.id] = record.thread
                }
            }
            activeThreads = Array(activeThreadsByID.values)
        }

        cache = cache.filter { seenURLs.contains($0.key) }
        return activeThreads.sorted {
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
    }

    private func cachedRecord(
        at fileURL: URL,
        allowsSubagent: Bool,
        cutoff: Date,
        resourceKeys: Set<URLResourceKey>,
        seenURLs: inout Set<URL>
    ) -> RolloutRecord? {
        guard fileURL.pathExtension == "jsonl",
              let values = try? fileURL.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true,
              let modificationDate = values.contentModificationDate,
              modificationDate >= cutoff else {
            return nil
        }

        let standardizedURL = fileURL.standardizedFileURL
        let fileSize = values.fileSize ?? 0
        seenURLs.insert(standardizedURL)
        let cached = cache[standardizedURL]
        if cached?.modificationDate == modificationDate,
           cached?.fileSize == fileSize,
           cached?.allowsSubagent == allowsSubagent {
            return cached?.record
        }

        let record = parseRollout(
            at: standardizedURL,
            updatedAt: modificationDate,
            allowsSubagent: allowsSubagent
        )
        cache[standardizedURL] = CachedRollout(
            modificationDate: modificationDate,
            fileSize: fileSize,
            allowsSubagent: allowsSubagent,
            record: record
        )
        return record
    }

    private func parseRollout(at url: URL, updatedAt: Date, allowsSubagent: Bool) -> RolloutRecord? {
        guard let metadata = readSessionMetadata(at: url), allowsSubagent || !metadata.isSubagent else {
            return nil
        }

        let latestEvent = latestTaskEvent(at: url)
        let activeStartedAt = latestEvent?.type == "task_started"
            ? latestEvent?.timestamp ?? updatedAt
            : nil

        let thread = ActiveThread(
            id: metadata.id,
            cwd: metadata.cwd,
            startedAt: activeStartedAt ?? updatedAt,
            updatedAt: updatedAt
        )
        return RolloutRecord(thread: thread, isActive: activeStartedAt != nil)
    }

    private func fallbackRolloutURLs(
        fileManager: FileManager,
        resourceKeys: Set<URLResourceKey>
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func indexedThreadRoots() -> [IndexedThreadRoot]? {
        guard let stateDatabase,
              FileManager.default.fileExists(atPath: stateDatabase.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            stateDatabase.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        let query = """
        WITH RECURSIVE thread_tree(
          root_id,
          root_cwd,
          member_id,
          rollout_path,
          member_updated
        ) AS (
          SELECT root.id, root.cwd, root.id, root.rollout_path, root.updated_at
          FROM threads AS root
          WHERE root.archived = 0
            AND NOT EXISTS (
              SELECT 1
              FROM thread_spawn_edges AS edge
              WHERE edge.child_thread_id = root.id
            )
          UNION ALL
          SELECT tree.root_id, tree.root_cwd, child.id, child.rollout_path, child.updated_at
          FROM thread_tree AS tree
          JOIN thread_spawn_edges AS edge ON edge.parent_thread_id = tree.member_id
          JOIN threads AS child ON child.id = edge.child_thread_id
          WHERE child.archived = 0
        ),
        recent_roots AS (
          SELECT root_id, MAX(member_updated) AS latest_updated
          FROM thread_tree
          GROUP BY root_id
          HAVING latest_updated >= ?
          ORDER BY latest_updated DESC, root_id DESC
          LIMIT 100
        )
        SELECT tree.root_id, tree.root_cwd, tree.rollout_path
        FROM thread_tree AS tree
        JOIN recent_roots AS recent ON recent.root_id = tree.root_id
        ORDER BY recent.latest_updated DESC, tree.root_id, tree.member_updated DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = Int64(Date().addingTimeInterval(-recentFileInterval).timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, cutoff)

        var rootsByID: [String: IndexedThreadRoot] = [:]
        var rootOrder: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let cwdPointer = sqlite3_column_text(statement, 1),
                  let pathPointer = sqlite3_column_text(statement, 2) else {
                continue
            }
            let id = String(cString: idPointer)
            let rolloutURL = URL(fileURLWithPath: String(cString: pathPointer))
            if rootsByID[id] == nil {
                rootOrder.append(id)
                rootsByID[id] = IndexedThreadRoot(
                    id: id,
                    cwd: URL(fileURLWithPath: String(cString: cwdPointer), isDirectory: true),
                    rolloutURLs: [rolloutURL]
                )
            } else {
                rootsByID[id]?.rolloutURLs.append(rolloutURL)
            }
        }
        return rootOrder.compactMap { rootsByID[$0] }
    }

    private func latestTaskEvent(at url: URL) -> (type: String, timestamp: Date?)? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let fileSize = try? handle.seekToEnd() else {
            return nil
        }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1_024
        let newline = UInt8(ascii: "\n")
        var position = fileSize
        var leadingFragment = Data()

        while position > 0 {
            let readStart = position > chunkSize ? position - chunkSize : 0
            let readCount = Int(position - readStart)
            do {
                try handle.seek(toOffset: readStart)
                guard let chunk = try handle.read(upToCount: readCount) else {
                    return nil
                }

                var combined = chunk
                combined.append(leadingFragment)
                var lines = combined.split(separator: newline, omittingEmptySubsequences: true)

                if readStart > 0, !lines.isEmpty {
                    leadingFragment = Data(lines.removeFirst())
                } else {
                    leadingFragment.removeAll(keepingCapacity: true)
                }

                for line in lines.reversed() {
                    if let event = taskEvent(in: Data(line)) {
                        return event
                    }
                }
            } catch {
                return nil
            }
            position = readStart
        }
        return leadingFragment.isEmpty ? nil : taskEvent(in: leadingFragment)
    }

    private func taskEvent(in lineData: Data) -> (type: String, timestamp: Date?)? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "event_msg",
              let payload = envelope["payload"] as? [String: Any],
              let eventType = payload["type"] as? String,
              ["task_started", "task_complete", "turn_aborted"].contains(eventType) else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (eventType, parseTimestamp(envelope["timestamp"], using: dateFormatter))
    }

    private func readSessionMetadata(at url: URL) -> (id: String, cwd: URL, isSubagent: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var lineData = Data()
        let newline = UInt8(ascii: "\n")
        let maximumMetadataBytes = 8 * 1_024 * 1_024

        while lineData.count < maximumMetadataBytes {
            guard let chunk = try? handle.read(upToCount: 64 * 1_024),
                  !chunk.isEmpty else {
                break
            }
            lineData.append(chunk)
            if let newlineIndex = lineData.firstIndex(of: newline) {
                lineData = lineData.prefix(upTo: newlineIndex)
                break
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "session_meta",
              let payload = envelope["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String else {
            return nil
        }

        return (
            id: id,
            cwd: URL(fileURLWithPath: cwd, isDirectory: true),
            isSubagent: payload["thread_source"] as? String == "subagent"
        )
    }

    private func parseTimestamp(_ value: Any?, using formatter: ISO8601DateFormatter) -> Date? {
        guard let timestamp = value as? String else {
            return nil
        }
        if let date = formatter.date(from: timestamp) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: timestamp)
    }
}
