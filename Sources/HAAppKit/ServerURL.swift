import Foundation

/// The address of Home Assistant, normalized: `http` or `https`, a host, no
/// trailing slash. A bare host like `homeassistant.local:8123` gets `http://`.
public struct ServerURL: Hashable, Sendable, CustomStringConvertible {
    public let base: URL

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        base = url
    }

    public var description: String { base.absoluteString }

    /// `ws(s)://<host>/api/websocket`.
    public var websocket: URL {
        var parts = URLComponents(url: api("websocket"), resolvingAgainstBaseURL: false)!
        parts.scheme = base.scheme?.lowercased() == "https" ? "wss" : "ws"
        return parts.url!
    }

    /// A REST endpoint under `/api/`, like `api("config")`.
    public func api(_ path: String) -> URL {
        base.appending(path: "api").appending(path: path)
    }

    /// The profile page where people create a long-lived access token.
    public var securityProfile: URL { base.appending(path: "profile").appending(path: "security") }
}
