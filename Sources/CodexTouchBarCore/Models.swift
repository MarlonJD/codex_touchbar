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
    public let unreadWorkingDirectories: [URL]

    public init(
        threads: [ActiveThread],
        weeklyLimit: WeeklyLimitUsage?,
        unreadWorkingDirectories: [URL] = []
    ) {
        self.threads = threads
        self.weeklyLimit = weeklyLimit
        self.unreadWorkingDirectories = unreadWorkingDirectories
    }
}

public struct ActiveThread: Equatable, Sendable {
    public let id: String
    public let cwd: URL
    public let startedAt: Date
    public let updatedAt: Date
    public let projectRecencyAt: Date

    public init(
        id: String,
        cwd: URL,
        startedAt: Date,
        updatedAt: Date,
        projectRecencyAt: Date? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.projectRecencyAt = projectRecencyAt ?? updatedAt
    }
}

public struct ProjectGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let threads: [ActiveThread]
    public let isUnnamed: Bool
    public let hasUnread: Bool

    public init(
        id: String,
        name: String,
        threads: [ActiveThread],
        isUnnamed: Bool,
        hasUnread: Bool = false
    ) {
        self.id = id
        self.name = name
        self.threads = threads
        self.isUnnamed = isUnnamed
        self.hasUnread = hasUnread
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
