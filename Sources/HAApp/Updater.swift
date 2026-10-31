import AppKit
import HAAppKit

/// Checks GitHub Releases for a newer HAApp: from HAApp > Check for Updates…
/// (⇧⌘U), from Settings > General, and on its own once a day when that's on.
/// A newer version opens an alert with Download, which opens the release page.
/// The repository comes from Info.plist (`HAUpdateRepo`), filled in by build.sh
/// from the git remote; a build without one can't check.
@Observable
final class Updater {
    static let shared = Updater()

    /// The running version, from Info.plist. A plain ./build.sh build is 0.1.
    let current: AppVersion
    /// `owner/name` on GitHub, or nil when this build doesn't know it.
    let repo: String?

    private(set) var isChecking = false
    /// The last result, shown in Settings > General.
    private(set) var lastOutcome: UpdateCheck.Outcome?

    var checksAutomatically: Bool = UserDefaults.standard.object(forKey: "updates.automatic") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(checksAutomatically, forKey: "updates.automatic")
            if checksAutomatically { startAutomaticChecks() }
        }
    }

    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "updates.lastCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "updates.lastCheck") }
    }

    /// A version the person chose to skip: automatic checks stay quiet about it.
    private var skipped: String? {
        get { UserDefaults.standard.string(forKey: "updates.skipped") }
        set { UserDefaults.standard.set(newValue, forKey: "updates.skipped") }
    }

    private var timer: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        current = AppVersion(info["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0.1")!
        repo = UpdateCheck.repo(info["HAUpdateRepo"] as? String ?? "")
    }

    var canCheck: Bool { repo != nil && !isChecking }

    /// Checks at launch when a day has passed, then every few hours while HAApp runs
    /// (it can live in the menu bar for weeks).
    func startAutomaticChecks() {
        guard timer == nil, repo != nil, !Store.isOverridden else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.checksAutomatically else { break }
                if UpdateCheck.isDue(lastCheck: self.lastCheck) { await self.check(userInitiated: false) }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
            self?.timer = nil
        }
    }

    /// From the menu or Settings: always says what happened. Automatic: speaks
    /// only when there's a new version the person hasn't skipped.
    func check(userInitiated: Bool) async {
        guard let repo, !isChecking else { return }
        isChecking = true
        let outcome = await UpdateCheck.check(current: current, repo: repo)
        isChecking = false
        lastOutcome = outcome
        if case .failed = outcome {} else { lastCheck = .now }

        switch outcome {
        case .available(let release):
            if userInitiated || skipped != release.version.description { offer(release) }
        case .upToDate(let version) where userInitiated:
            alert("HAApp is up to date", "Version \(version) is the newest version.")
        case .failed(let message) where userInitiated:
            alert("Can't check for updates", message)
        default:
            break
        }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "HAApp \(release.version) is available"
        alert.informativeText = "You have version \(current). Download the new version, quit HAApp, and replace the app in your Applications folder."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.page)
        case .alertThirdButtonReturn: skipped = release.version.description
        default: break
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
