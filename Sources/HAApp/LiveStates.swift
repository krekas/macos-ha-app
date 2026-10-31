import Foundation
import Observation
import HAAppKit

/// Live entity states from Home Assistant over one WebSocket that stays open:
/// `get_states`, then every `state_changed` event. Reconnects with backoff
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

    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var nextID = 10
    /// Toggles waiting for their answer: message id -> (entity id, state before).
    private var pending: [Int: (entityID: String, before: EntityState?)] = [:]

    private static let statesID = 1
    private static let subscribeID = 2
    private static let backoff: [Double] = [1, 2, 5, 10, 30]

    func start(server: ServerURL, token: String) {
        stop()
        task = Task { await run(server: server, token: token) }
    }

    func stop() {
        task?.cancel()
        task = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isLive = false
        pending = [:]
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
                try await Self.send(socket, LiveRequest.toggle(id: messageID, entityID: id))
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

    private enum Stop: Error { case rejected }

    private func run(server: ServerURL, token: String) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await session(server: server, token: token) { attempt = 0 }
            } catch Stop.rejected {
                isLive = false
                return
            } catch {}
            isLive = false
            pending = [:]
            guard !Task.isCancelled else { return }
            let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func session(server: ServerURL, token: String, connected: () -> Void) async throws {
        let socket = URLSession.shared.webSocketTask(with: server.websocket)
        // A big install's get_states runs to several megabytes; the default cap is 1 MB.
        socket.maximumMessageSize = 64 * 1024 * 1024
        socket.resume()
        self.socket = socket
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            if self.socket === socket { self.socket = nil }
        }
        while !Task.isCancelled {
            let data: Data
            switch try await socket.receive() {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            // A big get_states answer takes a moment to read: off the main thread.
            let message = await Task.detached { LiveMessage.parse(data) }.value
            switch message {
            case .authRequired:
                try await Self.send(socket, LiveRequest.auth(token: token))
            case .authOK:
                try await Self.send(socket, LiveRequest.getStates(id: Self.statesID))
                try await Self.send(socket, LiveRequest.subscribeStateChanges(id: Self.subscribeID))
            case .authInvalid:
                throw Stop.rejected
            case .states(_, let list):
                states = Dictionary(list.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
                isLive = true
                connected()
            case .changed(let entityID, let state):
                states[entityID] = state
            case .result(let id, let success, let error):
                finish(id, success: success, error: error)
            case .other, nil:
                break
            }
        }
    }

    private static func send(_ socket: URLSessionWebSocketTask, _ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
