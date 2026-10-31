import HAAppKit
import ServiceManagement
import SwiftUI

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
    private let loginItem = LoginItem.shared

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
                        Button("Disconnect") { model.disconnect() }
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

        Section {
            Toggle(isOn: $preferences.showInMenuBar) {
                Text("Show in menu bar")
                Text("Open your items from the menu bar. HAApp keeps running there after you close its window.")
            }
            Toggle(isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) })) {
                Text("Open at login")
                Text("HAApp starts in the menu bar when you log in, without a window or a Dock icon.")
            }
            .disabled(!preferences.showInMenuBar)
        } header: {
            Text("Menu Bar")
        } footer: {
            loginFooter
        }
        .onChange(of: preferences.showInMenuBar) { _, shown in
            // Open at login means "start in the menu bar": it goes with the icon.
            if !shown && loginItem.isOn { loginItem.set(false) }
        }
        .onAppear { loginItem.refresh() }

        UpdatesSection()
    }

    @ViewBuilder
    private var loginFooter: some View {
        if let error = loginItem.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if loginItem.needsApproval {
            HStack(spacing: Space.sm) {
                Text("Allow HAApp in System Settings to open it at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .tint(Palette.accentText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func connect() {
        guard model.connection.canConnect else { return }
        Task { await model.connect() }
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

/// Settings > General > Updates: the running version, Check Now, and the daily check.
private struct UpdatesSection: View {
    @Bindable private var updater = Updater.shared

    var body: some View {
        Section {
            LabeledContent {
                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                    .disabled(!updater.canCheck)
            } label: {
                Text("HAApp \(updater.current.description)")
                status
            }
            Toggle(isOn: $updater.checksAutomatically) {
                Text("Check for updates automatically")
                Text("Once a day, HAApp asks GitHub for a newer version and tells you when there is one.")
            }
            .disabled(updater.repo == nil)
        } header: {
            Text("Updates")
        } footer: {
            if updater.repo == nil {
                Text("This build doesn't know where HAApp is published. Releases made with tools/release.sh do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if updater.isChecking {
            Text("Checking…")
        } else {
            switch updater.lastOutcome {
            case .available(let release): Text("Version \(release.version.description) is available")
            case .upToDate: Text("Up to date")
            case .failed: Text("The last check didn't finish")
            case nil: EmptyView()
            }
        }
    }
}
