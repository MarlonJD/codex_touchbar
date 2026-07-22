import Foundation

public enum RefreshPolicy {
    public static func pollInterval(codexIsFrontmost: Bool) -> TimeInterval? {
        codexIsFrontmost ? 5 : nil
    }

    public static func shouldApply(previous: [ProjectGroup]?, next: [ProjectGroup]) -> Bool {
        previous != next
    }
}
