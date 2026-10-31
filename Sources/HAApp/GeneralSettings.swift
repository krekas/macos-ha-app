import SwiftUI
import HAAppKit

/// App settings kept in UserDefaults. Observable, so the App's scenes follow them.
/// (`@AppStorage` in the App struct sends `MenuBarExtra(isInserted:)` into an update loop.)
@Observable
final class Preferences {
    static let shared = Preferences()

    /// Show the HAApp icon in the menu bar. Off by default: HAApp is a window app first.
    var showInMenuBar: Bool = UserDefaults.standard.bool(forKey: "menuBar.show") {
        didSet {
            guard showInMenuBar != oldValue else { return }
            UserDefaults.standard.set(showInMenuBar, forKey: "menuBar.show")
        }
    }
}

/// Settings > General: the Home Assistant connection and the menu bar icon.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        @Bindable var connection = model.connection
        Section {
            // Fixed-width fields: a pasted token is 180+ characters and would
            // otherwise stretch the row. Long text scrolls inside the field.
            LabeledContent("Server URL") {
                TextField("Server URL", text: $connection.serverText, prompt: Text("http://homeassistant.local:8123"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                    .settingsField()
            }
            LabeledContent("Access token") {
                SecureField("Access token", text: $connection.tokenText, prompt: Text("Paste a long-lived access token"))
                    .onSubmit(connect)
                    .settingsField()
            }
            LabeledContent {
                HStack(spacing: Space.sm) {
                    if connection.isConnected {
                        Button("Disconnect") { connection.disconnect() }
                    }
                    Button("Connect", action: connect)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!connection.canConnect || connection.status == .connecting)
                }
            } label: {
                ConnectionStatusLine(connection: connection)
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("Create an access token in Home Assistant: Profile → Security → Long-lived access tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section("Menu Bar") {
            Toggle(isOn: $preferences.showInMenuBar) {
                Text("Show in menu bar")
                Text("Open your items from the menu bar. HAApp keeps running there after you close its window.")
            }
        }
    }

    private func connect() {
        guard model.connection.canConnect else { return }
        Task { await model.connection.connect() }
    }
}

private extension View {
    /// A text field at a fixed width on the trailing edge of a Settings row.
    func settingsField() -> some View {
        labelsHidden()
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: Layout.settingsFieldWidth)
    }
}

/// A dot plus words, so the status never rests on color alone.
struct ConnectionStatusLine: View {
    let connection: Connection

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                switch connection.status {
                case .connecting:
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                case .connected:
                    Image(systemName: "circle.fill").foregroundStyle(.green).imageScale(.small)
                    Text("Connected")
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).imageScale(.small)
                    Text("Not connected")
                case .notConnected:
                    Image(systemName: "circle").foregroundStyle(.secondary).imageScale(.small)
                    Text("Not connected")
                }
            }
            detail
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        switch connection.status {
        case .connected(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .failed(let result, let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if result == .rejected, let server = ServerURL(connection.serverText) {
                Link("Open Profile", destination: server.securityProfile)
                    .font(.caption)
                    .tint(Palette.accentText)
            }
        default:
            EmptyView()
        }
    }
}
