import Foundation

struct RolloutTaskEvent: Equatable, Sendable {
    let type: String
    let timestamp: Date?
}

struct RolloutTailUpdate: Equatable, Sendable {
    let latestEvent: RolloutTaskEvent?
    let latestWeeklyLimit: WeeklyLimitUsage?
    let processedOffset: UInt64
    let bytesRead: Int
}

enum RolloutTailReader {
    static func readChanges(at url: URL, from offset: UInt64) throws -> RolloutTailUpdate {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return RolloutTailUpdate(
                latestEvent: nil,
                latestWeeklyLimit: nil,
                processedOffset: offset,
                bytesRead: data.count
            )
        }

        let completedData = data.prefix(through: lastNewline)
        var latestEvent: RolloutTaskEvent?
        var latestWeeklyLimit: WeeklyLimitUsage?
        for line in completedData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let events = lineEvents(in: Data(line))
            latestEvent = events.task ?? latestEvent
            latestWeeklyLimit = events.weeklyLimit ?? latestWeeklyLimit
        }

        return RolloutTailUpdate(
            latestEvent: latestEvent,
            latestWeeklyLimit: latestWeeklyLimit,
            processedOffset: offset + UInt64(completedData.count),
            bytesRead: data.count
        )
    }

    static func endOfLastCompleteLine(at url: URL, fileSize: UInt64) throws -> UInt64 {
        guard fileSize > 0 else {
            return 0
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize: UInt64 = 64 * 1_024
        var position = fileSize
        while position > 0 {
            let readStart = position > chunkSize ? position - chunkSize : 0
            try handle.seek(toOffset: readStart)
            let data = try handle.read(upToCount: Int(position - readStart)) ?? Data()
            if let newline = data.lastIndex(of: UInt8(ascii: "\n")) {
                return readStart + UInt64(newline + 1)
            }
            position = readStart
        }
        return 0
    }

    static func taskEvent(in lineData: Data) -> RolloutTaskEvent? {
        lineEvents(in: lineData).task
    }

    static func weeklyLimit(in lineData: Data) -> WeeklyLimitUsage? {
        lineEvents(in: lineData).weeklyLimit
    }

    static func lineEvents(
        in lineData: Data
    ) -> (task: RolloutTaskEvent?, weeklyLimit: WeeklyLimitUsage?) {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "event_msg",
              let payload = envelope["payload"] as? [String: Any] else {
            return (nil, nil)
        }

        let timestamp = parseTimestamp(envelope["timestamp"])
        let task: RolloutTaskEvent?
        if let eventType = payload["type"] as? String,
           ["task_started", "task_complete", "turn_aborted"].contains(eventType) {
            task = RolloutTaskEvent(type: eventType, timestamp: timestamp)
        } else {
            task = nil
        }

        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any],
              let recordedAt = timestamp else {
            return (task, nil)
        }

        let weeklyWindow = ["primary", "secondary"]
            .compactMap { rateLimits[$0] as? [String: Any] }
            .first { window in
                (window["window_minutes"] as? NSNumber)?.intValue == 7 * 24 * 60
            }
        guard let weeklyWindow,
              let usedPercent = (weeklyWindow["used_percent"] as? NSNumber)?.doubleValue else {
            return (task, nil)
        }

        let resetsAt = (weeklyWindow["resets_at"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return (
            task,
            WeeklyLimitUsage(
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                recordedAt: recordedAt
            )
        )
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let timestamp = value as? String else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: timestamp) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: timestamp)
    }
}
