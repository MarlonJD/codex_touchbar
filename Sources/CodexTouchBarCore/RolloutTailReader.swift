import Foundation

struct RolloutTaskEvent: Equatable, Sendable {
    let type: String
    let timestamp: Date?
}

struct RolloutTailUpdate: Equatable, Sendable {
    let latestEvent: RolloutTaskEvent?
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
                processedOffset: offset,
                bytesRead: data.count
            )
        }

        let completedData = data.prefix(through: lastNewline)
        var latestEvent: RolloutTaskEvent?
        for line in completedData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if let event = taskEvent(in: Data(line)) {
                latestEvent = event
            }
        }

        return RolloutTailUpdate(
            latestEvent: latestEvent,
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
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "event_msg",
              let payload = envelope["payload"] as? [String: Any],
              let eventType = payload["type"] as? String,
              ["task_started", "task_complete", "turn_aborted"].contains(eventType) else {
            return nil
        }

        return RolloutTaskEvent(
            type: eventType,
            timestamp: parseTimestamp(envelope["timestamp"])
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
