import Foundation

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

    public init(id: String, name: String, threads: [ActiveThread], isUnnamed: Bool) {
        self.id = id
        self.name = name
        self.threads = threads
        self.isUnnamed = isUnnamed
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
