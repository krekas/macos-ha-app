import AppKit
import ServiceManagement

/// Open at login (S-030), through `SMAppService.mainApp`. The toggle shows the
/// real registration, read again whenever HAApp comes to the front, because
/// people can also turn it off in System Settings > General > Login Items.
@Observable
final class LoginItem {
    static let shared = LoginItem()

    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var error: String?

    /// On, or waiting for approval in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LoginItem.shared.refresh() }
        }
    }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        // Tests and snapshots never change the real login items.
        guard !Store.isOverridden else { return }
        error = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = on ? "Couldn't add HAApp to your login items." : "Couldn't remove HAApp from your login items."
        }
        refresh()
    }

    /// True when macOS opened HAApp because it is a login item. Read in
    /// applicationDidFinishLaunching: the launch event isn't current before it.
    /// APP_LOGIN=1 pretends, for trying it out without logging out.
    static var launchedAtLogin: Bool {
        if ProcessInfo.processInfo.environment["APP_LOGIN"] == "1" { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication
        else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
