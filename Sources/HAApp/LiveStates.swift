import Foundation
import Observation
import HAAppKit

/// Live entity states from Home Assistant over one WebSocket that stays open:
/// Subscribes before fetching `get_states`, then applies `state_changed`
/// events. Reconnects with backoff
/// (1, 2, 5, 10, then every 30 seconds) after the socket drops, for example
/// after sleep or a network change. Items read their values from here and
/// turn things on and off through it.
@Observable
final class LiveStates {
    /// Every entity's state, by entity id. Kept after the socket drops, so
    /// items show their last known value while it reconnects.
    private(set) var states: [String: EntityState] = [:]
    /// True between the first `get_states` answer and the socket dropping.
    private(set) var isLive = false
    /// Why the last toggle of an entity failed, shown for a few seconds.
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var socket: (any LiveSocket)?
    @ObservationIgnored private let makeSocket: (ServerURL) -> any LiveSocket
    @ObservationIgnored private let heartbeatInterval: Duration
    @ObservationIgnored private let responseTimeout: Duration
    @ObservationIgnored private var awaitingPong: Int?

    init(heartbeatInterval: Duration = .seconds(20), responseTimeout: Duration = .seconds(10),
         makeSocket: @escaping (ServerURL) -> any LiveSocket = { HomeAssistantSocket(server: $0) }) {
        self.makeSocket = makeSocket
        self.heartbeatInterval = heartbeatInterval
        self.responseTimeout = responseTimeout
    }
    @ObservationIgnored private var nextID = 10
    /// Toggles waiting for their answer: message id -> (entity id, state before).
    @ObservationIgnored private var pending: [Int: (entityID: String, before: EntityState?)] = [:]

    // Home Assistant requires command IDs to increase within a connection.
    private static let subscribeID = 1
    private static let statesID = 2
    private static let backoff: [Double] = [1, 2, 5, 10, 30]

    func start(server: ServerURL, token: String) {
        stop()
        task = Task { await run(server: server, token: token) }
    }

    func stop() {
        task?.cancel()
        task = nil
        socket?.cancel()
        socket = nil
        isLive = false
        pending = [:]
        awaitingPong = nil
    }

    /// Fills in states without a server, for snapshots and the self-test.
    func preview(_ sample: [EntityState]) {
        stop()
        states = Dictionary(sample.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
        isLive = true
    }

    /// Turns a light, switch, remote, or other on/off entity on or off. The
    /// item flips at once; Home Assistant's next state confirms it, and a
    /// failed call puts the old state back.
    func toggle(_ entityID: String) {
        guard isLive, let id = EntityID(entityID), id.isToggleable else { return }
        let before = states[entityID]
        if var flipped = before, !flipped.isUnavailable {
            flipped.state = flipped.isOn ? "off" : "on"
            states[entityID] = flipped
        }
        errors[entityID] = nil
        // Snapshots and the self-test have no socket: the flip is the whole story.
        guard let socket else { return }
        let messageID = nextID
        nextID += 1
        pending[messageID] = (entityID, before)
        Task {
            do {
                try await socket.send(LiveRequest.toggle(id: messageID, entityID: id))
            } catch {
                finish(messageID, success: false, error: "Home Assistant didn't get the request.")
            }
        }
    }

    private func finish(_ messageID: Int, success: Bool, error: String?) {
        guard let toggle = pending.removeValue(forKey: messageID), !success else { return }
        if let before = toggle.before { states[toggle.entityID] = before }
        let message = error ?? "Home Assistant refused."
        errors[toggle.entityID] = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            if errors[toggle.entityID] == message { errors[toggle.entityID] = nil }
        }
    }

    // MARK: The socket

    private enum Stop: Error { case rejected, setupFailed }

    private func run(server: ServerURL, token: String) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await session(server: server, token: token) { attempt = 0 }
            } catch Stop.rejected {
                guard !Task.isCancelled else { return }
                isLive = false
                return
            } catch {}
            // A replaced connection must never mark its successor offline.
            guard !Task.isCancelled else { return }
            isLive = false
            pending = [:]
            let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func session(server: ServerURL, token: String, connected: () -> Void) async throws {
        try Task.checkCancellation()
        let socket = makeSocket(server)
        self.socket = socket
        awaitingPong = nil
        let heartbeat = Task { await monitor(socket) }
        defer {
            heartbeat.cancel()
            socket.cancel()
            if self.socket === socket { self.socket = nil }
        }
        while !Task.isCancelled {
            let message = try await socket.receive()
            try Task.checkCancellation()
            switch message {
            case .authRequired:
                try await socket.send(LiveRequest.auth(token: token))
            case .authOK:
                try await socket.send(LiveRequest.subscribeStateChanges(id: Self.subscribeID))
            case .authInvalid:
                throw Stop.rejected
            case .states(let id, let list) where id == Self.statesID:
                states = Dictionary(list.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
                isLive = true
                connected()
            case .changed(let entityID, let state):
                states[entityID] = state
            case .result(let id, let success, let error):
                if id == Self.subscribeID {
                    guard success else { throw Stop.setupFailed }
                    try await socket.send(LiveRequest.getStates(id: Self.statesID))
                } else if id == Self.statesID {
                    throw Stop.setupFailed
                } else {
                    finish(id, success: success, error: error)
                }
            case .pong(let id):
                if awaitingPong == id { awaitingPong = nil }
            case .other, .states, nil:
                break
            }
        }
    }

    /// An idle but healthy server still answers ping. A stalled handshake,
    /// snapshot, or heartbeat closes the socket so the receive loop reconnects.
    private func monitor(_ socket: any LiveSocket) async {
        do {
            try await Task.sleep(for: heartbeatInterval + responseTimeout)
            guard self.socket === socket else { return }
            guard isLive else { socket.cancel(); return }
            while !Task.isCancelled {
                let id = nextID
                nextID += 1
                awaitingPong = id
                // The timeout must also cover a send stalled by a dead network.
                let sender = Task {
                    do {
                        try await socket.send(LiveRequest.ping(id: id))
                    } catch {
                        if !Task.isCancelled, self.socket === socket { socket.cancel() }
                    }
                }
                defer { sender.cancel() }
                try await Task.sleep(for: responseTimeout)
                guard self.socket === socket else { return }
                guard awaitingPong == nil else { socket.cancel(); return }
                try await Task.sleep(for: heartbeatInterval)
            }
        } catch {
            if !Task.isCancelled, self.socket === socket { socket.cancel() }
        }
    }
}
