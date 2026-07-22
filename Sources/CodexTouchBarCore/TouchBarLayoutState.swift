public enum TouchBarSettingPicker: Equatable, Sendable {
    case effort
    case speed
}

public enum TouchBarLayoutMode: Equatable, Sendable {
    case projects
    case setting(TouchBarSettingPicker)
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
