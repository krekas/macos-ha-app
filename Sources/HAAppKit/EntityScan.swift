import Foundation

/// Why a scan didn't finish.
public enum EntityScanError: Error, Equatable, Sendable {
    case rejected
    case unreachable
    case timedOut
    case failed(String)

    public func message(server: ServerURL) -> String {
        switch self {
        case .rejected:
            "Home Assistant rejected the access token. Connect again in General."
        case .unreachable:
            "Can't reach Home Assistant at \(server). The list shows the last scan."
        case .timedOut:
            "Home Assistant took too long to answer. Try again."
        case .failed(let reason):
            "The scan didn't finish: \(reason)"
        }
    }
}

/// Reads every entity, device, and area from Home Assistant over one short
/// WebSocket session: authenticate, send four commands, collect the results.
/// The REST API has no device or area info, so this can't use it.
public enum EntityScan {
    /// The commands, by message id.
    static let commands: [Int: String] = [
        1: "get_states",
        2: "config/entity_registry/list",
        3: "config/device_registry/list",
        4: "config/area_registry/list",
    ]

    public static func run(server: ServerURL, token: String, timeout: Duration = .seconds(30),
                           session: URLSession = .shared) async throws(EntityScanError) -> EntityCatalog {
        let socket = session.webSocketTask(with: server.websocket)
        // A big install's get_states runs to several megabytes; the default cap is 1 MB.
        socket.maximumMessageSize = 64 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        do {
            return try await withThrowingTaskGroup(of: EntityCatalog.self) { group in
                group.addTask { try await exchange(socket, token: token, server: server) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw EntityScanError.timedOut
                }
                defer { group.cancelAll() }
                guard let catalog = try await group.next() else { throw EntityScanError.timedOut }
                return catalog
            }
        } catch let error as EntityScanError {
            throw error
        } catch {
            throw .unreachable
        }
    }

    private static func exchange(_ socket: URLSessionWebSocketTask, token: String, server: ServerURL) async throws -> EntityCatalog {
        var reply = try await receive(socket)
        guard reply.type == "auth_required" else { throw EntityScanError.failed("unexpected greeting \(reply.type)") }
        try await send(socket, ["type": "auth", "access_token": token])
        reply = try await receive(socket)
        switch reply.type {
        case "auth_ok": break
        case "auth_invalid": throw EntityScanError.rejected
        default: throw EntityScanError.failed("unexpected reply \(reply.type)")
        }
        for (id, type) in commands.sorted(by: { $0.key < $1.key }) {
            try await send(socket, ["id": id, "type": type])
        }
        var results: [Int: Data] = [:]
        while results.count < commands.count {
            let message = try await receive(socket)
            guard message.type == "result", let id = message.id, commands[id] != nil else { continue }
            guard message.success == true, let result = message.result else {
                throw EntityScanError.failed(message.errorMessage ?? "\(commands[id]!) failed")
            }
            results[id] = result
        }
        do {
            return try EntityCatalog.build(states: results[1]!, entityRegistry: results[2]!,
                                           deviceRegistry: results[3]!, areaRegistry: results[4]!,
                                           server: server.description)
        } catch {
            throw EntityScanError.failed("Home Assistant sent a list HAApp can't read.")
        }
    }

    private static func send(_ socket: URLSessionWebSocketTask, _ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private static func receive(_ socket: URLSessionWebSocketTask) async throws -> SocketMessage {
        let data: Data
        switch try await socket.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw EntityScanError.failed("unknown message")
        }
        guard let message = SocketMessage(data) else { throw EntityScanError.failed("a message HAApp can't read") }
        return message
    }
}

/// One WebSocket message from Home Assistant. `result` stays raw JSON, so
/// the catalog decodes it with its own types.
struct SocketMessage {
    let type: String
    let id: Int?
    let success: Bool?
    let result: Data?
    let errorMessage: String?

    init?(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        self.type = type
        id = json["id"] as? Int
        success = json["success"] as? Bool
        result = json["result"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        errorMessage = (json["error"] as? [String: Any])?["message"] as? String
    }
}
