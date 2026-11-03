import Foundation
import HAAppKit

/// The live feed's transport. Self-tests supply a scripted connection.
protocol LiveSocket: AnyObject {
    func send(_ object: [String: Any]) async throws
    func receive() async throws -> LiveMessage?
    func cancel()
}

final class HomeAssistantSocket: LiveSocket {
    private let task: URLSessionWebSocketTask

    init(server: ServerURL) {
        task = URLSession.shared.webSocketTask(with: server.websocket)
        // A large installation's get_states can exceed the default 1 MB cap.
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
    }

    func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func receive() async throws -> LiveMessage? {
        let data: Data
        switch try await task.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return nil
        }
        return await Task.detached { LiveMessage.parse(data) }.value
    }

    func cancel() { task.cancel(with: .goingAway, reason: nil) }
}
