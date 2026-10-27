import Foundation
import Testing
@testable import CodexTouchBar
import CodexTouchBarCore

@Test func reusesTheAccountSnapshotDuringTheRefreshInterval() async {
    let client = CodexAccountRateLimitClient(
        refreshInterval: 60,
        maximumCacheAge: 300
    ) { _, requestedAt in
        WeeklyLimitUsage(
            usedPercent: requestedAt.timeIntervalSince1970 == 100 ? 9 : 12,
            resetsAt: nil,
            recordedAt: requestedAt
        )
    }

    let initial = await client.weeklyLimit(
        at: Date(timeIntervalSince1970: 100)
    )
    let cached = await client.weeklyLimit(
        at: Date(timeIntervalSince1970: 110)
    )

    #expect(initial?.remainingPercent == 91)
    #expect(cached?.remainingPercent == 91)
    #expect(cached?.recordedAt == Date(timeIntervalSince1970: 100))
}

@Test func emptyAccountResultClearsAnEarlierPercentage() async {
    let client = CodexAccountRateLimitClient(refreshInterval: 1) { _, date in
        date.timeIntervalSince1970 < 101
            ? WeeklyLimitUsage(usedPercent: 1, resetsAt: nil, recordedAt: date) : nil
    }
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 100))?.remainingPercent == 99)
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 102)) == nil)
}

@Test func expiredAllowanceIsNotShownAfterTheWeeklyReset() async {
    let client = CodexAccountRateLimitClient(refreshInterval: 60) { _, date in
        WeeklyLimitUsage(usedPercent: 28, resetsAt: Date(timeIntervalSince1970: 105), recordedAt: date)
    }
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 100))?.remainingPercent == 72)
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 106)) == nil)
}

@Test func stalledAccountServerIsTerminatedWithinTheDeadline() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    let start = Date()
    #expect(throws: (any Error).self) {
        try CodexAppServerRateLimitFetcher.fetch(executableURL: url, recordedAt: start, timeout: 0.2)
    }
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func anInitialFailureRetriesWithoutWaitingForTheNormalRefreshInterval() async {
    let client = CodexAccountRateLimitClient(refreshInterval: 60) { _, date in
        if date.timeIntervalSince1970 < 105 { throw CodexAppServerRateLimitFetcher.FetchError.connectionClosed }
        return WeeklyLimitUsage(usedPercent: 4, resetsAt: nil, recordedAt: date)
    }
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 100)) == nil)
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 104)) == nil)
    #expect(await client.weeklyLimit(at: Date(timeIntervalSince1970: 105))?.remainingPercent == 96)
}
