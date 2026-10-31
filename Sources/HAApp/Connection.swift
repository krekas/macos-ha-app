import Foundation
import Observation
import HAAppKit

/// The server URL and access token, and whether Home Assistant accepts them.
/// The URL is saved in UserDefaults, the token in the Keychain, and only
/// after Connect succeeds. Test and snapshot runs keep both in memory.
@Observable
final class Connection {
    enum Status: Equatable {
        case notConnected
        case connecting
        case connected(String)
        case failed(ConnectionResult, String)
    }

    /// What the fields show. Saved on a successful Connect.
    var serverText: String
    var tokenText: String
    private(set) var status: Status = .notConnected
    /// The saved, normalized URL.
    private(set) var server: ServerURL?

    private let persists: Bool
    private static let urlKey = "connection.serverURL"
    private static let keychain = KeychainItem(service: "com.krekas.haapp", account: "access-token")

    init(persists: Bool) {
        self.persists = persists
        let url = persists ? UserDefaults.standard.string(forKey: Self.urlKey) ?? "" : ""
        serverText = url
        tokenText = persists ? Self.keychain.read() ?? "" : ""
        server = ServerURL(url)
    }

    var isConnected: Bool { if case .connected = status { true } else { false } }
    var hasSavedToken: Bool { server != nil && !tokenText.isEmpty }
    var canConnect: Bool { ServerURL(serverText) != nil && !tokenText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Tries the fields against Home Assistant and saves them when it answers.
    func connect() async {
        guard let url = ServerURL(serverText) else {
            status = .notConnected
            return
        }
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .connecting
        let result = await ConnectionCheck.run(server: url, token: token)
        if case .connected = result {
            serverText = url.description
            tokenText = token
            server = url
            if persists {
                UserDefaults.standard.set(url.description, forKey: Self.urlKey)
                Self.keychain.save(token)
            }
            status = .connected(result.message(server: url))
        } else {
            status = .failed(result, result.message(server: url))
        }
    }

    /// Forgets the access token. The server URL stays for next time.
    func disconnect() {
        tokenText = ""
        status = .notConnected
        if persists { Self.keychain.delete() }
    }
}
