import Foundation

public struct DesktopThreadIdentity: Hashable, Sendable {
    public let hostID: String
    public let threadID: String

    public init(hostID: String, threadID: String) {
        self.hostID = hostID
        self.threadID = threadID
    }
}

public struct ComposerSettings: Equatable, Sendable {
    public let model: String?
    public let effort: String?
    public let serviceTier: String?

    public init(model: String?, effort: String?, serviceTier: String?) {
        self.model = model
        self.effort = effort
        self.serviceTier = serviceTier
    }

    public var modelAndEffortTitle: String? {
        guard let model, !model.isEmpty else { return nil }
        let words = model.split(separator: "-").map(String.init)
        let modelTitle = words.map { $0.lowercased() == "gpt" ? "GPT" : $0.capitalized }
            .joined(separator: " ").replacingOccurrences(of: "GPT ", with: "GPT-")
        let effortTitle: String?
        switch effort {
        case "xhigh": effortTitle = "Extra High"
        case .some(let value): effortTitle = value.capitalized
        case nil: effortTitle = nil
        }
        return [modelTitle, effortTitle].compactMap { $0 }.joined(separator: " ")
    }
}

/// Stores only task metadata. Transcript, tool output and instruction fields are discarded.
public struct DesktopThreadState {
    private var entries: [DesktopThreadIdentity: Entry] = [:]
    private var readStates: [DesktopThreadIdentity: Bool] = [:]

    private struct Entry {
        var metadata: [String: Any]
        var revision: Int
        let owner: String
    }

    private static let scalarKeys: Set<String> = [
        "id", "hostId", "title", "cwd", "createdAt", "updatedAt", "recencyAt",
        "hasUnreadTurn", "ephemeral", "sideConversation", "parentThreadId",
        "threadSource", "workspaceKind", "latestModel", "latestReasoningEffort",
    ]
    private static let nestedKeys: [String: Set<String>] = [
        "threadRuntimeStatus": ["type"],
        "latestThreadSettings": ["model", "effort", "serviceTier"],
    ]

    public init() {}

    public var identities: Set<DesktopThreadIdentity> { Set(entries.keys) }

    /// Returns false on a revision gap; the caller must request a fresh snapshot.
    @discardableResult
    public mutating func receive(
        identity: DesktopThreadIdentity,
        owner: String,
        change: [String: Any]
    ) -> Bool {
        guard let revision = change["revision"] as? Int else { return false }
        switch change["type"] as? String {
        case "snapshot":
            guard let state = change["conversationState"] as? [String: Any],
                  state["id"] as? String == identity.threadID,
                  state["hostId"] as? String == identity.hostID else { return false }
            entries[identity] = Entry(metadata: Self.sanitize(state), revision: revision, owner: owner)
        case "patches":
            guard var entry = entries[identity], entry.owner == owner,
                  change["baseRevision"] as? Int == entry.revision,
                  let patches = change["patches"] as? [[String: Any]] else {
                entries[identity] = nil
                return false
            }
            for patch in patches {
                guard let path = patch["path"] as? [Any],
                      let operation = patch["op"] as? String else { continue }
                if path.isEmpty, let value = patch["value"] as? [String: Any] {
                    entry.metadata = Self.sanitize(value)
                    continue
                }
                guard let key = path.first as? String else { continue }
                if path.count == 1 {
                    if Self.scalarKeys.contains(key) {
                        entry.metadata[key] = operation == "remove" ? nil : patch["value"]
                    } else if let allowed = Self.nestedKeys[key] {
                        entry.metadata[key] = (patch["value"] as? [String: Any])?
                            .filter { allowed.contains($0.key) }
                    } else if key == "latestCollaborationMode" {
                        entry.metadata[key] = Self.collaborationSettings(patch["value"])
                    }
                } else if key == "latestCollaborationMode", path[1] as? String == "settings" {
                    if path.count == 2 {
                        entry.metadata[key] = (patch["value"] as? [String: Any])?
                            .filter { ["model", "reasoning_effort"].contains($0.key) }
                    } else if path.count == 3, let field = path[2] as? String,
                              ["model", "reasoning_effort"].contains(field) {
                        var settings = entry.metadata[key] as? [String: Any] ?? [:]
                        settings[field] = operation == "remove" ? nil : patch["value"]
                        entry.metadata[key] = settings
                    }
                } else if path.count == 2, let field = path[1] as? String,
                          Self.nestedKeys[key]?.contains(field) == true {
                    var nested = entry.metadata[key] as? [String: Any] ?? [:]
                    nested[field] = operation == "remove" ? nil : patch["value"]
                    entry.metadata[key] = nested
                }
            }
            entry.revision = revision
            entries[identity] = entry
        default: return false
        }
        return true
    }

    public mutating func removeOwner(_ clientID: String) {
        for (identity, entry) in entries where entry.owner == clientID { readStates[identity] = nil }
        entries = entries.filter { $0.value.owner != clientID }
    }

    public mutating func reset() {
        entries.removeAll()
        readStates.removeAll()
    }

    public mutating func remove(_ identity: DesktopThreadIdentity) {
        entries[identity] = nil
        readStates[identity] = nil
    }

    /// Read receipts are a separate desktop event, independent of task-stream revisions.
    public mutating func updateReadState(for identity: DesktopThreadIdentity, hasUnreadTurn: Bool) {
        readStates[identity] = hasUnreadTurn
    }

    public func settings(for identity: DesktopThreadIdentity) -> ComposerSettings? {
        guard let state = entries[identity]?.metadata else { return nil }
        let settings = state["latestThreadSettings"] as? [String: Any]
        let collaboration = state["latestCollaborationMode"] as? [String: Any]
        return ComposerSettings(
            model: collaboration?["model"] as? String ?? state["latestModel"] as? String ?? settings?["model"] as? String,
            effort: collaboration?["reasoning_effort"] as? String ?? state["latestReasoningEffort"] as? String ?? settings?["effort"] as? String,
            serviceTier: settings?["serviceTier"] as? String
        )
    }

    public func identity(matchingSelectedLabel label: String) -> DesktopThreadIdentity? {
        let matches = entries.filter { _, entry in
            guard let title = entry.metadata["title"] as? String, !title.isEmpty else { return false }
            return label == title || label.hasPrefix(title + " ")
        }
        return matches.count == 1 ? matches.first?.key : nil
    }

    public func threads() -> [ActiveThread] {
        entries.compactMap { identity, entry in
            let state = entry.metadata
            guard state["ephemeral"] as? Bool != true,
                  state["sideConversation"] as? Bool != true,
                  state["parentThreadId"] as? String == nil,
                  state["threadSource"] as? String != "subagent" else { return nil }
            let status = (state["threadRuntimeStatus"] as? [String: Any])?["type"] as? String
            let active = status == "active"
            let unread = !active && (readStates[identity] ?? (state["hasUnreadTurn"] as? Bool ?? false))
            guard active || unread else { return nil }
            let cwd = state["cwd"] as? String ?? "/"
            let cloud = identity.hostID == "durable"
            let projectless = state["workspaceKind"] as? String == "projectless"
            return ActiveThread(
                id: identity.threadID,
                cwd: URL(fileURLWithPath: cwd),
                startedAt: Self.date(state["createdAt"]),
                updatedAt: Self.date(state["updatedAt"]),
                projectRecencyAt: Self.date(state["recencyAt"] ?? state["updatedAt"]),
                isActive: active,
                isUnread: unread,
                hostID: identity.hostID,
                projectName: cloud ? "Bulut" : projectless ? ProjectGrouper.tasksGroupName : nil
            )
        }
    }

    public func merging(localThreads: [ActiveThread]) -> [ActiveThread] {
        // A live idle/disconnected snapshot must also override an old task_started rollout.
        localThreads.filter { entries[$0.identity] == nil } + threads()
    }

    private static func sanitize(_ state: [String: Any]) -> [String: Any] {
        var result = state.filter { scalarKeys.contains($0.key) }
        for (key, allowed) in nestedKeys {
            result[key] = (state[key] as? [String: Any])?.filter { allowed.contains($0.key) }
        }
        result["latestCollaborationMode"] = collaborationSettings(state["latestCollaborationMode"])
        return result
    }

    private static func collaborationSettings(_ value: Any?) -> [String: Any]? {
        ((value as? [String: Any])?["settings"] as? [String: Any])?
            .filter { ["model", "reasoning_effort"].contains($0.key) }
    }

    private static func date(_ value: Any?) -> Date {
        let timestamp = (value as? NSNumber)?.doubleValue ?? 0
        return Date(timeIntervalSince1970: timestamp > 1e12 ? timestamp / 1_000 : timestamp)
    }
}

public struct DesktopIPCFrameDecoder: Sendable {
    private var buffer = Data()
    public static let maximumFrameSize = 64 * 1_024 * 1_024
    public enum FrameError: Error { case invalidLength }

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
            guard length > 0, length <= Self.maximumFrameSize else {
                buffer.removeAll()
                throw FrameError.invalidLength
            }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer.removeFirst(4 + length)
        }
        return frames
    }

    public static func encode(_ data: Data) -> Data {
        var length = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(data)
        return frame
    }
}
