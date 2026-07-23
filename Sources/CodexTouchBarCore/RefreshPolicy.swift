import Foundation

public enum RefreshPolicy {
    public static let timerRunLoopMode = RunLoop.Mode.common

    public static func pollInterval(codexIsFrontmost: Bool) -> TimeInterval? {
        codexIsFrontmost ? 1 : nil
    }

    public static func shouldApply(previous: [ProjectGroup]?, next: [ProjectGroup]) -> Bool {
        previous != next
    }
}
