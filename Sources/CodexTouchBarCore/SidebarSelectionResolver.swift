public enum SidebarSelectionRow: Equatable, Sendable {
    case project(name: String, minY: Double, height: Double)
    case selectedProject(name: String, minY: Double, height: Double)
    case selectedTask(minY: Double, height: Double)

    fileprivate var minY: Double {
        switch self {
        case let .project(_, minY, _),
             let .selectedProject(_, minY, _),
             let .selectedTask(minY, _):
            minY
        }
    }

    fileprivate var height: Double {
        switch self {
        case let .project(_, _, height),
             let .selectedProject(_, _, height),
             let .selectedTask(_, height):
            height
        }
    }
}

public enum SidebarSelectionResolver {
    public static func projectName(from rows: [SidebarSelectionRow]) -> String? {
        let visibleRows = rows.filter { $0.height > 1 }
        if let selectedProjectName = visibleRows.compactMap({ row -> String? in
            guard case let .selectedProject(name, _, _) = row else {
                return nil
            }
            return name
        }).first {
            return selectedProjectName
        }

        guard let selectedTask = visibleRows.first(where: {
            if case .selectedTask = $0 {
                return true
            }
            return false
        }) else {
            return nil
        }

        let containingProject = visibleRows.compactMap { row -> (String, Double)? in
            let project: (String, Double)
            switch row {
            case let .project(name, minY, _), let .selectedProject(name, minY, _):
                project = (name, minY)
            case .selectedTask:
                return nil
            }
            return project.1 <= selectedTask.minY ? project : nil
        }
        .max { $0.1 < $1.1 }

        return containingProject?.0 ?? ProjectGrouper.tasksGroupName
    }
}
