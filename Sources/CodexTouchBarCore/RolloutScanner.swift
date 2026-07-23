import CSQLite
import Foundation

public actor RolloutScanner {
    private struct CachedRollout {
        let modificationDate: Date
        let fileSize: Int
        let processedOffset: UInt64
        let allowsSubagent: Bool
        let record: RolloutRecord?
    }

    private struct RolloutRecord {
        let thread: ActiveThread
        let isActive: Bool
        let weeklyLimit: WeeklyLimitUsage?
    }

    private struct LatestRolloutEvents {
        let task: RolloutTaskEvent?
        let weeklyLimit: WeeklyLimitUsage?
    }

    private struct GlobalStateValues {
        let unreadThreadIDs: Set<String>
        let selectedProjectRoots: [URL]
    }

    private struct IndexedThreadRoot {
        let id: String
        let cwd: URL
        let updatedAt: Date
        let projectRecencyAt: Date
        var rolloutURLs: [URL]
    }

    private let sessionsRoot: URL
    private let stateDatabase: URL?
    private let globalStateFile: URL?
    private let recentFileInterval: TimeInterval
    private var cache: [URL: CachedRollout] = [:]
    private var lastGlobalStateValues: GlobalStateValues?

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        stateDatabase: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        globalStateFile: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json"),
        recentFileInterval: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.sessionsRoot = sessionsRoot
        self.stateDatabase = stateDatabase
        self.globalStateFile = globalStateFile
        self.recentFileInterval = recentFileInterval
    }

    public func scan() -> [ActiveThread] {
        scanSnapshot().threads
    }

    public func scanSnapshot() -> RolloutSnapshot {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        let cutoff = Date().addingTimeInterval(-recentFileInterval)
        let globalState = globalStateValues(fileManager: fileManager)
        let unreadThreadIDs = globalState.unreadThreadIDs
        var seenURLs = Set<URL>()
        var weeklyLimits: [WeeklyLimitUsage] = []
        let visibleThreads: [ActiveThread]

        if let indexedRoots = indexedThreadRoots() {
            visibleThreads = indexedRoots.compactMap { root in
                let records = root.rolloutURLs.compactMap { url in
                    cachedRecord(
                        at: url,
                        allowsSubagent: true,
                        cutoff: cutoff,
                        resourceKeys: resourceKeys,
                        seenURLs: &seenURLs
                    )
                }
                weeklyLimits.append(contentsOf: records.compactMap(\.weeklyLimit))
                let activeRecords = records.filter(\.isActive)
                let activeStartedAt = activeRecords.map(\.thread.startedAt).min()
                let isUnread = activeStartedAt == nil && unreadThreadIDs.contains(root.id)

                guard activeStartedAt != nil || isUnread else {
                    return nil
                }
                return ActiveThread(
                    id: root.id,
                    cwd: root.cwd,
                    startedAt: activeStartedAt ?? root.updatedAt,
                    updatedAt: root.updatedAt,
                    projectRecencyAt: root.projectRecencyAt,
                    isActive: activeStartedAt != nil,
                    isUnread: isUnread
                )
            }
        } else {
            var visibleThreadsByID: [String: ActiveThread] = [:]
            for url in fallbackRolloutURLs(fileManager: fileManager, resourceKeys: resourceKeys) {
                guard let record = cachedRecord(
                    at: url,
                    allowsSubagent: false,
                    cutoff: cutoff,
                    resourceKeys: resourceKeys,
                    seenURLs: &seenURLs
                ) else {
                    continue
                }
                if let weeklyLimit = record.weeklyLimit {
                    weeklyLimits.append(weeklyLimit)
                }
                let isUnread = !record.isActive && unreadThreadIDs.contains(record.thread.id)
                guard record.isActive || isUnread else {
                    continue
                }
                let visibleThread = ActiveThread(
                    id: record.thread.id,
                    cwd: record.thread.cwd,
                    startedAt: record.thread.startedAt,
                    updatedAt: record.thread.updatedAt,
                    projectRecencyAt: record.thread.projectRecencyAt,
                    isActive: record.isActive,
                    isUnread: isUnread
                )
                let existing = visibleThreadsByID[record.thread.id]
                if existing == nil || visibleThread.updatedAt > existing!.updatedAt {
                    visibleThreadsByID[record.thread.id] = visibleThread
                }
            }
            visibleThreads = Array(visibleThreadsByID.values)
        }

        cache = cache.filter { seenURLs.contains($0.key) }
        let sortedThreads = visibleThreads.sorted {
            if $0.isUnread != $1.isUnread {
                return $0.isUnread
            }
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
        let latestWeeklyLimit = weeklyLimits.max {
            $0.recordedAt < $1.recordedAt
        }
        return RolloutSnapshot(
            threads: sortedThreads,
            weeklyLimit: latestWeeklyLimit,
            selectedProjectRoots: globalState.selectedProjectRoots
        )
    }

    private func globalStateValues(fileManager: FileManager) -> GlobalStateValues {
        let emptyValues = GlobalStateValues(
            unreadThreadIDs: [],
            selectedProjectRoots: []
        )
        guard let globalStateFile,
              let data = fileManager.contents(atPath: globalStateFile.path),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return lastGlobalStateValues ?? emptyValues
        }

        let atomState = root["electron-persisted-atom-state"] as? [String: Any]
        let unreadByHost = atomState?["unread-thread-ids-by-host-v1"] as? [String: Any]
        let unreadThreadIDs = Set(unreadByHost?["local"] as? [String] ?? [])

        var selectedProjectRoots: [URL] = []
        if let selectedProject = root["selected-project"] as? [String: Any],
           selectedProject["type"] as? String == "local",
           let projectID = selectedProject["projectId"] as? String,
           let localProjects = root["local-projects"] as? [String: Any],
           let localProject = localProjects[projectID] as? [String: Any],
           let rootPaths = localProject["rootPaths"] as? [String] {
            selectedProjectRoots = rootPaths
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                .sorted { $0.path < $1.path }
        }

        let stateValues = GlobalStateValues(
            unreadThreadIDs: unreadThreadIDs,
            selectedProjectRoots: selectedProjectRoots
        )
        lastGlobalStateValues = stateValues
        return stateValues
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

        if let cached,
           cached.allowsSubagent == allowsSubagent,
           fileSize > cached.fileSize,
           let record = cached.record,
           let update = try? RolloutTailReader.readChanges(
               at: standardizedURL,
               from: cached.processedOffset
           ) {
            let updatedRecord = updateRecord(
                record,
                with: update,
                updatedAt: modificationDate
            )
            cache[standardizedURL] = CachedRollout(
                modificationDate: modificationDate,
                fileSize: fileSize,
                processedOffset: update.processedOffset,
                allowsSubagent: allowsSubagent,
                record: updatedRecord
            )
            return updatedRecord
        }

        let record = parseRollout(
            at: standardizedURL,
            updatedAt: modificationDate,
            allowsSubagent: allowsSubagent
        )
        let processedOffset = (try? RolloutTailReader.endOfLastCompleteLine(
            at: standardizedURL,
            fileSize: UInt64(fileSize)
        )) ?? UInt64(fileSize)
        cache[standardizedURL] = CachedRollout(
            modificationDate: modificationDate,
            fileSize: fileSize,
            processedOffset: processedOffset,
            allowsSubagent: allowsSubagent,
            record: record
        )
        return record
    }

    private func updateRecord(
        _ record: RolloutRecord,
        with update: RolloutTailUpdate,
        updatedAt: Date
    ) -> RolloutRecord {
        let isActive: Bool
        let startedAt: Date
        switch update.latestEvent?.type {
        case "task_started":
            isActive = true
            startedAt = update.latestEvent?.timestamp ?? updatedAt
        case "task_complete", "turn_aborted":
            isActive = false
            startedAt = record.thread.startedAt
        default:
            isActive = record.isActive
            startedAt = record.thread.startedAt
        }

        return RolloutRecord(
            thread: ActiveThread(
                id: record.thread.id,
                cwd: record.thread.cwd,
                startedAt: startedAt,
                updatedAt: updatedAt,
                isActive: isActive
            ),
            isActive: isActive,
            weeklyLimit: update.latestWeeklyLimit ?? record.weeklyLimit
        )
    }

    private func parseRollout(at url: URL, updatedAt: Date, allowsSubagent: Bool) -> RolloutRecord? {
        guard let metadata = readSessionMetadata(at: url), allowsSubagent || !metadata.isSubagent else {
            return nil
        }

        let latestEvents = latestRolloutEvents(at: url)
        let activeStartedAt = latestEvents.task?.type == "task_started"
            ? latestEvents.task?.timestamp ?? updatedAt
            : nil

        let thread = ActiveThread(
            id: metadata.id,
            cwd: metadata.cwd,
            startedAt: activeStartedAt ?? updatedAt,
            updatedAt: updatedAt,
            isActive: activeStartedAt != nil
        )
        return RolloutRecord(
            thread: thread,
            isActive: activeStartedAt != nil,
            weeklyLimit: latestEvents.weeklyLimit
        )
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
        WITH RECURSIVE recent_members(member_id) AS (
          SELECT id
          FROM threads
          WHERE archived = 0
            AND updated_at >= ?
          UNION
          SELECT edge.parent_thread_id
          FROM recent_members AS recent
          JOIN thread_spawn_edges AS edge ON edge.child_thread_id = recent.member_id
          JOIN threads AS parent ON parent.id = edge.parent_thread_id
          WHERE parent.archived = 0
        ),
        recent_roots(
          root_id,
          root_cwd,
          root_updated,
          root_project_recency_ms
        ) AS (
          SELECT root.id,
                 root.cwd,
                 root.updated_at,
                 (
                   SELECT MAX(project_thread.recency_at_ms)
                   FROM threads AS project_thread
                   WHERE project_thread.archived = 0
                     AND project_thread.cwd = root.cwd
                 )
          FROM recent_members AS recent
          JOIN threads AS root ON root.id = recent.member_id
          WHERE NOT EXISTS (
            SELECT 1
            FROM thread_spawn_edges AS edge
            WHERE edge.child_thread_id = root.id
          )
          ORDER BY root.updated_at DESC, root.id DESC
          LIMIT 100
        ),
        thread_tree(
          root_id,
          root_cwd,
          root_updated,
          root_project_recency_ms,
          member_id,
          rollout_path,
          member_updated
        ) AS (
          SELECT root.root_id,
                 root.root_cwd,
                 root.root_updated,
                 root.root_project_recency_ms,
                 root.root_id,
                 thread.rollout_path,
                 thread.updated_at
          FROM recent_roots AS root
          JOIN threads AS thread ON thread.id = root.root_id
          UNION ALL
          SELECT tree.root_id, tree.root_cwd, tree.root_updated,
                 tree.root_project_recency_ms,
                 child.id, child.rollout_path, child.updated_at
          FROM thread_tree AS tree
          JOIN thread_spawn_edges AS edge ON edge.parent_thread_id = tree.member_id
          JOIN threads AS child ON child.id = edge.child_thread_id
          WHERE child.archived = 0
        )
        SELECT tree.root_id,
               tree.root_cwd,
               tree.rollout_path,
               tree.root_updated,
               tree.root_project_recency_ms
        FROM thread_tree AS tree
        ORDER BY tree.root_updated DESC, tree.root_id, tree.member_updated DESC
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
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3))),
                    projectRecencyAt: Date(
                        timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)) / 1_000
                    ),
                    rolloutURLs: [rolloutURL]
                )
            } else {
                rootsByID[id]?.rolloutURLs.append(rolloutURL)
            }
        }
        return rootOrder.compactMap { rootsByID[$0] }
    }

    private func latestRolloutEvents(at url: URL) -> LatestRolloutEvents {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let fileSize = try? handle.seekToEnd() else {
            return LatestRolloutEvents(task: nil, weeklyLimit: nil)
        }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1_024
        let newline = UInt8(ascii: "\n")
        var position = fileSize
        var leadingFragment = Data()
        var latestTask: RolloutTaskEvent?
        var latestWeeklyLimit: WeeklyLimitUsage?

        while position > 0 {
            let readStart = position > chunkSize ? position - chunkSize : 0
            let readCount = Int(position - readStart)
            do {
                try handle.seek(toOffset: readStart)
                guard let chunk = try handle.read(upToCount: readCount) else {
                    return LatestRolloutEvents(
                        task: latestTask,
                        weeklyLimit: latestWeeklyLimit
                    )
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
                    let events = RolloutTailReader.lineEvents(in: Data(line))
                    latestTask = latestTask ?? events.task
                    latestWeeklyLimit = latestWeeklyLimit ?? events.weeklyLimit
                    if latestTask != nil, latestWeeklyLimit != nil {
                        return LatestRolloutEvents(
                            task: latestTask,
                            weeklyLimit: latestWeeklyLimit
                        )
                    }
                }
            } catch {
                return LatestRolloutEvents(
                    task: latestTask,
                    weeklyLimit: latestWeeklyLimit
                )
            }
            position = readStart
        }
        if !leadingFragment.isEmpty {
            let events = RolloutTailReader.lineEvents(in: leadingFragment)
            latestTask = latestTask ?? events.task
            latestWeeklyLimit = latestWeeklyLimit ?? events.weeklyLimit
        }
        return LatestRolloutEvents(task: latestTask, weeklyLimit: latestWeeklyLimit)
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

}
