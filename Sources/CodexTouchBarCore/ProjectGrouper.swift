import Foundation

public struct ProjectGrouper: Sendable {
    public static let unnamedProjectID = "__unnamed_project__"

    private let scratchRoot: URL
    private let homeDirectory: URL

    public init(
        scratchRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Codex", isDirectory: true),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.scratchRoot = scratchRoot.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func groups(from threads: [ActiveThread]) -> [ProjectGroup] {
        var grouped: [String: (name: String, isUnnamed: Bool, threads: [ActiveThread])] = [:]

        for thread in threads {
            let identity = projectIdentity(for: thread.cwd)
            var entry = grouped[identity.id] ?? (identity.name, identity.isUnnamed, [])
            entry.threads.append(thread)
            grouped[identity.id] = entry
        }

        return grouped.map { id, entry in
            ProjectGroup(
                id: id,
                name: entry.name,
                threads: entry.threads.sorted {
                    if $0.startedAt == $1.startedAt {
                        return $0.id < $1.id
                    }
                    return $0.startedAt < $1.startedAt
                },
                isUnnamed: entry.isUnnamed
            )
        }
        .sorted { lhs, rhs in
            if lhs.isUnnamed != rhs.isUnnamed {
                return !lhs.isUnnamed
            }
            let lhsUpdatedAt = lhs.threads.map(\.projectRecencyAt).max() ?? .distantPast
            let rhsUpdatedAt = rhs.threads.map(\.projectRecencyAt).max() ?? .distantPast
            if lhsUpdatedAt != rhsUpdatedAt {
                return lhsUpdatedAt > rhsUpdatedAt
            }
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return comparison == .orderedAscending
        }
    }

    private func projectIdentity(for workingDirectory: URL) -> (id: String, name: String, isUnnamed: Bool) {
        let workingDirectory = workingDirectory.standardizedFileURL

        if let repositoryRoot = nearestGitRoot(startingAt: workingDirectory) {
            return (repositoryRoot.path, repositoryRoot.lastPathComponent, false)
        }

        if workingDirectory.isContained(in: scratchRoot) {
            return (Self.unnamedProjectID, "Unnamed Project", true)
        }

        let name = workingDirectory.lastPathComponent.isEmpty
            ? "Unnamed Project"
            : workingDirectory.lastPathComponent
        return (workingDirectory.path, name, name == "Unnamed Project")
    }

    private func nearestGitRoot(startingAt directory: URL) -> URL? {
        var candidate = directory
        let stopPath = homeDirectory.deletingLastPathComponent().path

        while candidate.path != stopPath && candidate.path != "/" {
            let gitEntry = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitEntry.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private extension URL {
    func isContained(in parent: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = standardizedFileURL.pathComponents
        guard childComponents.count >= parentComponents.count else {
            return false
        }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}
