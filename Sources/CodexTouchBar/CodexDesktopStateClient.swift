import CodexTouchBarCore
import Foundation
import Network
import CSQLite
import OSLog

/// A read-only subscriber to the desktop's existing task stream, including remote hosts.
@MainActor
final class CodexDesktopStateClient {
    private let socketURL: URL
    private let queue = DispatchQueue(label: "dev.marlonjd.CodexTouchBar.desktop-state")
    private var connection: NWConnection?
    private var decoder = DesktopIPCFrameDecoder()
    private var clientID: String?
    private var subscriptions: Set<DesktopThreadIdentity> = []
    private var pendingSubscriptions: Set<DesktopThreadIdentity> = []
    private var reconnectTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private(set) var state = DesktopThreadState()
    private(set) var isConnected = false
    private let logger = Logger(subsystem: "dev.marlonjd.CodexTouchBar", category: "thread-read-state")

    init(socketURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/ipc/ipc.sock")) {
        self.socketURL = socketURL
    }

    func start() {
        guard connection == nil else { return }
        let connection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] update in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                switch update {
                case .ready:
                    self.send([
                        "type": "request", "requestId": UUID().uuidString,
                        "sourceClientId": "initializing-client", "version": 0,
                        "method": "initialize", "params": ["clientType": "codex-touchbar"],
                    ])
                    self.receive(on: connection)
                case .failed, .waiting:
                    self.reconnect()
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        catalogTask?.cancel()
        catalogTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        clientID = nil
        isConnected = false
        state.reset()
        decoder = DesktopIPCFrameDecoder()
        subscriptions.removeAll()
        pendingSubscriptions.removeAll()
    }

    private func reconnect() {
        stop()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1_024) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                do {
                    if let data {
                        for frame in try self.decoder.append(data) {
                            if let message = try JSONSerialization.jsonObject(with: frame) as? [String: Any] {
                                self.handle(message)
                            }
                        }
                    }
                    if complete || error != nil { self.reconnect() }
                    else { self.receive(on: connection) }
                } catch { self.reconnect() }
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        let method = message["method"] as? String
        if message["type"] as? String == "client-discovery-request" {
            // We observe metadata only; never claim ownership or handle app commands.
            if let requestID = message["requestId"] as? String {
                send(["type": "client-discovery-response", "requestId": requestID,
                      "response": ["canHandle": false]])
            }
            return
        }
        if method == "initialize", message["resultType"] as? String == "success",
           let result = message["result"] as? [String: Any], let id = result["clientId"] as? String {
            clientID = id
            isConnected = true
            let pending = pendingSubscriptions
            pendingSubscriptions.removeAll()
            for identity in pending { subscribe(identity) }
            catalogTask = Task { [weak self] in
                while !Task.isCancelled {
                    let identities = await Task.detached(priority: .utility) {
                        Self.catalogIdentities()
                    }.value
                    guard !Task.isCancelled, let self else { return }
                    for identity in identities { self.subscribe(identity) }
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            return
        }
        guard message["type"] as? String == "broadcast",
              let params = message["params"] as? [String: Any],
              message["sourceClientId"] as? String != clientID else { return }
        if method == "client-status-changed", let owner = params["clientId"] as? String {
            if params["status"] as? String == "disconnected" {
                let previous = state.identities
                state.removeOwner(owner)
                subscriptions.subtract(previous.subtracting(state.identities))
            } else if params["status"] as? String == "connected", owner != clientID {
                // A remote host can connect after we seeded its IDs from the catalog.
                for identity in subscriptions { announce(identity, targetClientID: owner) }
            }
            return
        }
        guard let host = params["hostId"] as? String,
              let thread = params["conversationId"] as? String else { return }
        let identity = DesktopThreadIdentity(hostID: host, threadID: thread)
        switch method {
        case "thread-read-state-changed":
            guard message["version"] as? Int == 3,
                  let unread = params["hasUnreadTurn"] as? Bool,
                  let context = params["context"] as? [String: Any],
                  let hostKey = context["executionHostKey"] as? String,
                  hostKey.hasPrefix(host + ":") else { return }
            state.updateReadState(for: identity, hasUnreadTurn: unread)
            logger.notice("Read receipt applied; unread=\(unread, privacy: .public)")
        case "thread-stream-following-changed":
            if params["following"] as? Bool == true { subscribe(identity) }
        case "thread-stream-state-changed":
            guard message["version"] as? Int == 11,
                  let owner = message["sourceClientId"] as? String,
                  let change = params["change"] as? [String: Any] else { return }
            if !state.receive(identity: identity, owner: owner, change: change) {
                subscriptions.remove(identity)
                subscribe(identity)
            }
        case "thread-archived":
            state.remove(identity)
            subscriptions.remove(identity)
            if let clientID {
                send(["type": "broadcast", "method": "thread-stream-following-changed",
                      "sourceClientId": clientID, "version": 1,
                      "params": ["hostId": host, "conversationId": thread, "following": false]])
            }
        default: break
        }
    }

    private func subscribe(_ identity: DesktopThreadIdentity) {
        guard clientID != nil else {
            pendingSubscriptions.insert(identity)
            return
        }
        guard subscriptions.insert(identity).inserted else { return }
        announce(identity)
    }

    private func announce(_ identity: DesktopThreadIdentity, targetClientID: String? = nil) {
        guard let clientID else { return }
        var message: [String: Any] = [
            "type": "broadcast", "method": "thread-stream-following-changed",
            "sourceClientId": clientID, "version": 1,
            "params": ["hostId": identity.hostID, "conversationId": identity.threadID, "following": true],
        ]
        if let targetClientID { message["targetClientIds"] = [targetClientID] }
        send(message)
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        connection?.send(content: DesktopIPCFrameDecoder.encode(data), completion: .contentProcessed { _ in })
    }

    /// Catalog seeding discovers remote tasks in collapsed sidebar projects without resuming them.
    nonisolated private static func catalogIdentities() -> [DesktopThreadIdentity] {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sqlite")
        // Codex uses distinct current catalogs for production and development distributions.
        return ["codex.db", "codex-dev.db"].flatMap {
            readCatalog(at: directory.appendingPathComponent($0))
        }
    }

    nonisolated private static func readCatalog(at url: URL) -> [DesktopThreadIdentity] {
        var database: OpaquePointer?
        defer { if let database { sqlite3_close(database) } }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { return [] }
        let query = """
        SELECT host_id, thread_id FROM (
          SELECT host_id, thread_id,
                 ROW_NUMBER() OVER (PARTITION BY host_id ORDER BY source_recency_at DESC) AS rank
          FROM local_thread_catalog
          WHERE missing_candidate = 0 AND source_kind != 'chatgpt'
            AND (thread_source IS NULL OR thread_source != 'subagent')
        ) WHERE rank <= 100
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var identities: [DesktopThreadIdentity] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let host = sqlite3_column_text(statement, 0), let thread = sqlite3_column_text(statement, 1) else { continue }
            identities.append(.init(hostID: String(cString: host), threadID: String(cString: thread)))
        }
        return identities
    }
}
