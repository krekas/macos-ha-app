import AppKit
import HAAppKit
import SwiftData
import SwiftUI

// HAApp: a Mac app for Home Assistant. It opens a window; the menu bar icon is
// optional (Settings > General > Show in menu bar). With the menu bar icon on,
// HAApp can open at login; then it runs in the menu bar only, with no window
// and no Dock icon, until you open its window.
//   HAApp                      the app
//   APP_STORE=<file> HAApp     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> HAApp   save a PNG of the menu and every Settings tab in light and dark mode, then quit
//   APP_SEED=1 HAApp           fill an empty /tmp store with sample groups and items (tools/snap.sh)
//   HAApp --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> HAApp      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 HAApp           draw the 8 pt grid and the layout probes over the window
//   APP_LOGIN=1 HAApp          start as if opened at login (menu bar only, when its icon is on)

@main
struct HAAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @Bindable private var preferences = Preferences.shared

    var body: some Scene {
        Window("HAApp", id: MainWindow.id) {
            MainView()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .defaultSize(width: Layout.mainDefaultWidth, height: Layout.mainDefaultHeight)
        .keyboardShortcut("0")
        .commands { EntityCommands(model: delegate.model) }

        MenuBarExtra("HAApp", systemImage: "house", isInserted: $preferences.showInMenuBar) {
            MenuView()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
                .themed()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here, not in the App, so seed data, the self-test, and snapshots
    /// can start at launch: the menu's views only load when it first opens.
    let model = AppModel(container: Store.makeContainer())

    /// Opened at login with the menu bar icon on: no window, no Dock icon.
    /// Set in applicationDidFinishLaunching, the first moment the launch event is current.
    private(set) static var startsInMenuBar = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.updateDockIcon() }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated { AppDelegate.updateDockIcon(closing: closing) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.startsInMenuBar = Presence.atLaunch(launchedAtLogin: LoginItem.launchedAtLogin,
                                                 showInMenuBar: Preferences.shared.showInMenuBar) == .menuBarOnly
        if Self.startsInMenuBar {
            // The main window already exists but isn't drawn yet: close it in this turn.
            NSApp.setActivationPolicy(.accessory)
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(MainWindow.id) == true {
                window.close()
            }
        }
        SeedData.insertIfRequested(into: model)
        SelfTest.runIfRequested(model: model)
        Snapshot.runIfRequested(model: model)
        // Checks the saved settings, so the status is right without a click.
        if !Store.isOverridden { Task { await model.checkSaved() } }
        // Opened from Finder, the Dock, or a script: come to the front, above other apps.
        // Opened at login: stay quietly in the menu bar.
        if !Self.startsInMenuBar { NSApp.activate() }
    }

    /// Closing the last window quits, unless the menu bar icon keeps HAApp running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if Snapshot.requested || SelfTest.requested { return false }
        return !Preferences.shared.showInMenuBar
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }

    /// The Dock icon shows while the main window or Settings is open. With
    /// every window closed and the menu bar icon on, HAApp lives in the menu bar only.
    static func updateDockIcon(closing: NSWindow? = nil) {
        if Snapshot.requested || SelfTest.requested { return }
        let hasOpenWindow = NSApp.windows.contains { window in
            window !== closing && window.isVisible && window.canBecomeMain && !(window is NSPanel)
        }
        let presence = Presence.current(hasOpenWindow: hasOpenWindow, showInMenuBar: Preferences.shared.showInMenuBar)
        let policy: NSApplication.ActivationPolicy = presence == .window ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }

    /// Opens the main window from the menu bar, with the Dock icon, in front.
    static func showMainWindow(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: MainWindow.id)
        NSApp.activate()
    }
}

enum MainWindow {
    static let id = "main"
}

/// Where the data lives: ~/Library/Application Support/HAApp/HAApp.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "HAApp", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "HAApp.store")
    }

    /// The saved entity list, beside the database: HAApp.entities.json.
    static var entitiesURL: URL {
        url.deletingPathExtension().appendingPathExtension("entities.json")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: MenuGroup.self, MenuItem.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}

/// Menu bar commands for the entity list.
struct EntityCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Rescan Entities") {
                Task { await model.rescanEntities() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.canRescan)
        }
        CommandGroup(after: .sidebar) {
            Button("Expand All Entity Sections") { model.entities.expandAll() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(model.settingsTab != .entities)
            Button("Collapse All Entity Sections") { model.entities.collapseAll() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(model.settingsTab != .entities)
        }
    }
}
