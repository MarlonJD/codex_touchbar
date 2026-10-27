import Foundation

public struct WeeklyLimitUsage: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let recordedAt: Date

    public init(usedPercent: Double, resetsAt: Date?, recordedAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.recordedAt = recordedAt
    }

    public var remainingPercent: Int {
        Int((100 - min(max(usedPercent, 0), 100)).rounded())
    }
}

public struct RolloutSnapshot: Equatable, Sendable {
    public let threads: [ActiveThread]
    public let weeklyLimit: WeeklyLimitUsage?
    public let selectedProjectRoots: [URL]

    public init(
        threads: [ActiveThread],
        weeklyLimit: WeeklyLimitUsage?,
        selectedProjectRoots: [URL] = []
    ) {
        self.threads = threads
        self.weeklyLimit = weeklyLimit
        self.selectedProjectRoots = selectedProjectRoots
    }
}

public struct ActiveThread: Equatable, Sendable {
    public let id: String
    public let cwd: URL
    public let startedAt: Date
    public let updatedAt: Date
    public let projectRecencyAt: Date
    public let isActive: Bool
    public let isUnread: Bool
    public let hostID: String
    public let projectName: String?

    public var identity: DesktopThreadIdentity { .init(hostID: hostID, threadID: id) }

    public var navigationURL: URL? {
        var url = URLComponents()
        url.scheme = "codex"
        url.host = "threads"
        url.path = "/\(id)"
        if hostID != "local" {
            url.queryItems = [URLQueryItem(name: "hostId", value: hostID)]
        }
        return url.url
    }

    public init(
        id: String,
        cwd: URL,
        startedAt: Date,
        updatedAt: Date,
        projectRecencyAt: Date? = nil,
        isActive: Bool = true,
        isUnread: Bool = false,
        hostID: String = "local",
        projectName: String? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.projectRecencyAt = projectRecencyAt ?? updatedAt
        self.isActive = isActive
        self.isUnread = isUnread
        self.hostID = hostID
        self.projectName = projectName
    }
}

public struct ProjectGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let threads: [ActiveThread]
    public let isUnnamed: Bool
    public let hasUnread: Bool
    public let isSelected: Bool
    public let hostID: String

    public var symbolName: String {
        switch hostID {
        case "local": "folder.fill"
        case "durable": "cloud.fill"
        default: "desktopcomputer"
        }
    }

    public init(
        id: String,
        name: String,
        threads: [ActiveThread],
        isUnnamed: Bool,
        hasUnread: Bool = false,
        isSelected: Bool = false,
        hostID: String = "local"
    ) {
        self.id = id
        self.name = name
        self.threads = threads
        self.isUnnamed = isUnnamed
        self.hasUnread = hasUnread
        self.isSelected = isSelected
        self.hostID = hostID
    }

    public func displayName(maxLength: Int = 20) -> String {
        guard maxLength > 1, name.count > maxLength else {
            return name
        }
        return String(name.prefix(maxLength - 1)) + "…"
    }
}

public struct ThreadCycler: Sendable {
    private var nextIndexes: [String: Int] = [:]

    public init() {}

    public mutating func nextThread(in group: ProjectGroup) -> ActiveThread? {
        guard !group.threads.isEmpty else {
            nextIndexes[group.id] = nil
            return nil
        }

        let nextIndex = (nextIndexes[group.id] ?? 0) % group.threads.count
        nextIndexes[group.id] = (nextIndex + 1) % group.threads.count
        return group.threads[nextIndex]
    }

    public mutating func retainGroups(_ groupIDs: Set<String>) {
        nextIndexes = nextIndexes.filter { groupIDs.contains($0.key) }
    }
}
