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
    public static let navigationButtonWidth = 17.0
    public static let navigationButtonHeight = 30.0
    public static let itemSpacing = 4.0
    public static let navigationSlotWidth = navigationButtonWidth + itemSpacing
    public static let compactWidth = 419.0
    public static let compactWidthWithWeeklyLimit = 369.0
    public static let expandedWidth = 569.0

    public static func needsExpansion(contentWidth: Double, hasWeeklyLimit: Bool, settingsExtraWidth: Double) -> Bool {
        contentWidth > width(for: .projects, hasWeeklyLimit: hasWeeklyLimit, settingsExtraWidth: settingsExtraWidth)
            + navigationSlotWidth
    }

    public static func width(
        for mode: TouchBarLayoutMode,
        hasWeeklyLimit: Bool,
        settingsExtraWidth: Double = 0
    ) -> Double {
        switch mode {
        case .expandedProjects:
            expandedWidth
        case .projects, .setting:
            max(120, (hasWeeklyLimit ? compactWidthWithWeeklyLimit : compactWidth) - settingsExtraWidth)
        }
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
