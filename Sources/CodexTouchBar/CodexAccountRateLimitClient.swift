import CodexTouchBarCore
import Foundation
import Darwin
import OSLog

actor CodexAccountRateLimitClient {
    typealias Fetcher = @Sendable (URL, Date) async throws -> WeeklyLimitUsage?

    private let codexExecutableURL: URL
    private let refreshInterval: TimeInterval
    private let maximumCacheAge: TimeInterval
    private let fetcher: Fetcher
    private var cachedUsage: WeeklyLimitUsage?
    private var lastAttemptAt: Date?
    private var lastAttemptFailed = false
    private let logger = Logger(subsystem: "dev.marlonjd.CodexTouchBar", category: "account-limit")

    init(
        codexExecutableURL: URL = URL(
            fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        ),
        refreshInterval: TimeInterval = 60,
        maximumCacheAge: TimeInterval = 5 * 60,
        fetcher: Fetcher? = nil
    ) {
        self.codexExecutableURL = codexExecutableURL
        self.refreshInterval = refreshInterval
        self.maximumCacheAge = maximumCacheAge
        self.fetcher = fetcher ?? { executableURL, recordedAt in
            try await Task.detached(priority: .utility) {
                try CodexAppServerRateLimitFetcher.fetch(
                    executableURL: executableURL,
                    recordedAt: recordedAt
                )
            }.value
        }
    }

    func weeklyLimit(at now: Date = Date()) async -> WeeklyLimitUsage? {
        let interval = lastAttemptFailed && freshCachedUsage(at: now) == nil ? min(5, refreshInterval) : refreshInterval
        if let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < interval {
            return freshCachedUsage(at: now)
        }

        lastAttemptAt = now
        do {
            // A successful empty response also clears data from an earlier account.
            cachedUsage = try await fetcher(codexExecutableURL, now)
            lastAttemptFailed = false
            logger.notice("Account limit refreshed; available=\(self.cachedUsage != nil, privacy: .public)")
        } catch {
            lastAttemptFailed = true
            logger.error("Account limit refresh failed: \(String(describing: error), privacy: .public)")
            // Never replace account data with unrelated rollout rate-limit buckets.
        }
        return freshCachedUsage(at: now)
    }

    private func freshCachedUsage(at now: Date) -> WeeklyLimitUsage? {
        guard let cachedUsage,
              now.timeIntervalSince(cachedUsage.recordedAt) <= maximumCacheAge,
              cachedUsage.resetsAt.map({ $0 > now }) ?? true else {
            return nil
        }
        return cachedUsage
    }
}

enum CodexAppServerRateLimitFetcher {
    private static let initializeRequestID = 1
    private static let rateLimitRequestID = 2

    enum FetchError: Error {
        case executableUnavailable
        case connectionClosed
        case invalidResponse
        case requestFailed
    }

    static func fetch(
        executableURL: URL,
        recordedAt: Date,
        timeout: TimeInterval = 8
    ) throws -> WeeklyLimitUsage? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw FetchError.executableUnavailable
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                // This is our short-lived read-only child, never the desktop's server.
                kill(process.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }

        let reader = JSONLineReader(handle: output.fileHandleForReading)
        try write(
            [
                "id": initializeRequestID,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex_touchbar",
                        "title": "Codex Touch Bar",
                        "version": Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "development",
                    ],
                ],
            ],
            to: input.fileHandleForWriting
        )
        guard try reader.message(withID: initializeRequestID)["error"] == nil else {
            throw FetchError.requestFailed
        }

        try write(
            ["method": "initialized"],
            to: input.fileHandleForWriting
        )
        try write(
            [
                "id": rateLimitRequestID,
                "method": "account/rateLimits/read",
            ],
            to: input.fileHandleForWriting
        )

        let response = try reader.message(withID: rateLimitRequestID)
        guard response["error"] == nil,
              let result = response["result"] as? [String: Any],
              let resultData = try? JSONSerialization.data(withJSONObject: result) else {
            throw FetchError.requestFailed
        }
        return AccountRateLimitParser.weeklyLimit(
            from: resultData,
            recordedAt: recordedAt
        )
    }

    private static func write(
        _ object: [String: Any],
        to handle: FileHandle
    ) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: data)
    }

    private final class JSONLineReader {
        private let handle: FileHandle
        private var buffer = Data()

        init(handle: FileHandle) {
            self.handle = handle
        }

        func message(withID expectedID: Int) throws -> [String: Any] {
            while true {
                if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = buffer.prefix(upTo: newlineIndex)
                    buffer.removeSubrange(...newlineIndex)
                    guard !line.isEmpty,
                          let object = try? JSONSerialization.jsonObject(with: line),
                          let message = object as? [String: Any],
                          (message["id"] as? NSNumber)?.intValue == expectedID else {
                        continue
                    }
                    return message
                }

                let data = handle.availableData
                guard !data.isEmpty else {
                    throw FetchError.connectionClosed
                }
                buffer.append(data)
            }
        }
    }
}
