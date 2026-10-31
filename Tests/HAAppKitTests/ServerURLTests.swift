import Foundation
import Testing
@testable import HAAppKit

@Test("Normalize server URLs", arguments: [
    ("http://homeassistant.local:8123/", "http://homeassistant.local:8123"),
    ("  https://ha.example.com// ", "https://ha.example.com"),
    ("homeassistant.local:8123", "http://homeassistant.local:8123"),
    ("HTTPS://ha.example.com/base", "HTTPS://ha.example.com/base"),
])
func normalizes(_ input: String, expected: String) throws {
    #expect(try #require(ServerURL(input)).description == expected)
}

@Test("Reject bad server URLs", arguments: ["", "   ", "ftp://ha.local", "http://", "/"])
func rejectsServer(_ input: String) {
    #expect(ServerURL(input) == nil)
}

@Test func websocketURL() throws {
    #expect(try #require(ServerURL("http://ha.local:8123/")).websocket.absoluteString == "ws://ha.local:8123/api/websocket")
    #expect(try #require(ServerURL("https://ha.example.com")).websocket.absoluteString == "wss://ha.example.com/api/websocket")
}

@Test func restURL() throws {
    #expect(try #require(ServerURL("http://ha.local:8123")).api("config").absoluteString == "http://ha.local:8123/api/config")
}

@Test func connectionResults() throws {
    let server = try #require(ServerURL("http://ha.local:8123"))
    let ok = ConnectionResult(status: 200, body: Data(#"{"version":"2026.10.1"}"#.utf8))
    #expect(ok == .connected(version: "2026.10.1"))
    #expect(ok.message(server: server) == "Connected to Home Assistant 2026.10.1")
    #expect(ConnectionResult(status: 401, body: Data()) == .rejected)
    #expect(ConnectionResult(status: 401, body: Data()).message(server: server).hasPrefix("Home Assistant rejected the access token."))
    #expect(ConnectionResult(status: 500, body: Data()) == .unexpected(status: 500))
    #expect(ConnectionResult.unreachable.message(server: server).hasPrefix("Can't reach Home Assistant at http://ha.local:8123."))
}
