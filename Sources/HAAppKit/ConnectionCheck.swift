import Foundation

/// The result of trying the server URL and access token against Home Assistant.
public enum ConnectionResult: Equatable, Sendable {
    case connected(version: String?)
    case rejected
    case unreachable
    case unexpected(status: Int)

    /// Reads the answer to `GET /api/config`.
    public init(status: Int, body: Data) {
        switch status {
        case 200..<300:
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            self = .connected(version: json?["version"] as? String)
        case 401, 403: self = .rejected
        default: self = .unexpected(status: status)
        }
    }

    /// What the status line says.
    public func message(server: ServerURL) -> String {
        switch self {
        case .connected(let version):
            "Connected to Home Assistant\(version.map { " \($0)" } ?? "")"
        case .rejected:
            "Home Assistant rejected the access token. Create a new one in your Home Assistant profile under Security."
        case .unreachable:
            "Can't reach Home Assistant at \(server). Check the server URL and that the server is running."
        case .unexpected(let status):
            "Home Assistant at \(server) answered with an error (HTTP \(status)). Check the server URL."
        }
    }
}

public enum ConnectionCheck {
    /// Asks Home Assistant for its config with the access token.
    public static func run(server: ServerURL, token: String, session: URLSession = .shared) async -> ConnectionResult {
        var request = URLRequest(url: server.api("config"), timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return ConnectionResult(status: status, body: data)
        } catch {
            return .unreachable
        }
    }
}
