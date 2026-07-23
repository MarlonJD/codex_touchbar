public enum TouchBarSettingPicker: Equatable, Sendable {
    case effort
    case speed
}

public enum TouchBarLayoutMode: Equatable, Sendable {
    case projects
    case expandedProjects
    case setting(TouchBarSettingPicker)
}

public enum TouchBarProjectStripMetrics {
    public static let navigationButtonWidth = 44.0
    public static let itemSpacing = 4.0
    public static let navigationSlotWidth = navigationButtonWidth + itemSpacing
    public static let compactWidth = 392.0
    public static let compactWidthWithWeeklyLimit = 342.0
    public static let expandedWidth = 590.0

    public static func width(
        for mode: TouchBarLayoutMode,
        hasWeeklyLimit: Bool
    ) -> Double {
        switch mode {
        case .expandedProjects:
            expandedWidth
        case .projects, .setting:
            hasWeeklyLimit ? compactWidthWithWeeklyLimit : compactWidth
        }
    }
}

public enum TouchBarSettingTitle {
    public static func mainTitle(baseTitle: String, selectedTitle _: String) -> String {
        baseTitle
    }
}

public struct TouchBarLayoutState: Equatable, Sendable {
    public private(set) var mode: TouchBarLayoutMode = .projects
    public var showsSystemCloseBox: Bool { true }

    public init() {}

    public mutating func show(_ picker: TouchBarSettingPicker) {
        mode = .setting(picker)
    }

    public mutating func expandProjects() {
        mode = .expandedProjects
    }

    public mutating func collapseProjects() {
        mode = .projects
    }

    public mutating func completeSelection() {
        mode = .projects
    }

    public mutating func cancel() {
        mode = .projects
    }

    public func closeBoxVisibility(afterPresentationSucceeded succeeded: Bool) -> Bool {
        succeeded ? showsSystemCloseBox : true
    }
}
