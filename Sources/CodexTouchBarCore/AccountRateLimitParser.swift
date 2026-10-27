import Foundation

public enum AccountRateLimitParser {
    public static func weeklyLimit(
        from data: Data,
        recordedAt: Date = Date()
    ) -> WeeklyLimitUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let response = object as? [String: Any] else {
            return nil
        }

        let snapshots = response["rateLimitsByLimitId"] as? [String: Any]
        let snapshot = snapshots?["codex"] as? [String: Any]
            ?? response["rateLimits"] as? [String: Any]
        let weeklyWindow = ["primary", "secondary"]
            .compactMap { snapshot?[$0] as? [String: Any] }
            .first {
                ($0["windowDurationMins"] as? NSNumber)?.intValue == 7 * 24 * 60
            }
        guard let weeklyWindow,
              let usedPercent = (weeklyWindow["usedPercent"] as? NSNumber)?.doubleValue else {
            return nil
        }

        let resetsAt = (weeklyWindow["resetsAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return WeeklyLimitUsage(
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            recordedAt: recordedAt
        )
    }
}
