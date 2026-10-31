import AppKit
import SwiftData
import HAAppKit
import ServiceManagement

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/HAApp-self.store ~/Applications/HAApp.app/Contents/MacOS/HAApp --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.context
            func items() -> [MenuItem] { (try? context.fetch(FetchDescriptor<MenuItem>())) ?? [] }

            let group = model.addGroup(title: "Office")
            let first = model.addItem(entityID: "light.desk_lamp", to: group)
            let second = model.addItem(entityID: " Sensor.Office_Power ", to: group)
            check("adding an entity creates an item", first != nil && items().count == 2)
            check("entity ids are normalized", second?.entityID == "sensor.office_power")
            check("items keep the order they were added", group.sortedItems.map(\.entityID) == ["light.desk_lamp", "sensor.office_power"])
            check("a malformed entity id is refused", model.addItem(entityID: "desk lamp", to: group) == nil)
            check("a custom name wins over the fallback", {
                first?.customName = "Desk"
                return first?.displayName == "Desk"
            }())
            check("a new group goes last", model.addGroup(title: "Kitchen").order == group.order + 1)
            if let first {
                model.remove(first)
                try? context.save()
                check("removing an item leaves the others", items().map(\.entityID) == ["sensor.office_power"])
            }

            // S-001: connect to a server that isn't there.
            let connection = model.connection
            check("Connect needs a URL and a token", !connection.canConnect)
            connection.serverText = "http://127.0.0.1:9/"
            connection.tokenText = "not-a-token"
            check("Connect is ready with a URL and a token", connection.canConnect)
            await connection.connect()
            if case .failed(let result, let message) = connection.status {
                check("an unreachable server says so", result == .unreachable
                      && message.hasPrefix("Can't reach Home Assistant at http://127.0.0.1:9."), message)
            } else {
                check("an unreachable server says so", false, "\(connection.status)")
            }
            check("a failed connect saves nothing", connection.server == nil)
            connection.disconnect()
            check("Disconnect clears the token", connection.tokenText.isEmpty && connection.status == .notConnected)

            // Entity list: saved after a scan, kept when a scan fails.
            let store = model.entities
            store.replace(with: SeedData.sampleCatalog)
            check("a scan is saved next to the database", EntityCatalog.load(from: store.url)?.entities.count == 12)
            let reloaded = EntityStore(url: store.url)
            check("the saved list loads at launch", reloaded.catalog == store.catalog)
            if let sample = ServerURL("http://homeassistant.local:8123"), let other = ServerURL("http://10.0.0.2:8123") {
                check("the same server needs no new scan", !store.needsScan(for: sample))
                check("another server needs a new scan", store.needsScan(for: other))
            }
            if let dead = ServerURL("http://127.0.0.1:9") {
                await store.scan(server: dead, token: "x")
                check("a failed scan keeps the last list", store.catalog?.entities.count == 12)
                check("a failed scan says why", store.scanError?.hasPrefix("Can't reach Home Assistant") == true, store.scanError ?? "nil")
            }
            check("Rescan needs a connection", !model.canRescan)
            let byDevice = store.catalog?.sections(by: .device) ?? []
            check("grouped by device, loose entities last", byDevice.first?.title == "Desk Lamp" && byDevice.last?.title == "No Device")
            check("search finds sensors by area", store.catalog?.sections(by: .type, matching: "office sensor")
                .flatMap(\.entities).map(\.entityID) == ["sensor.office_energy", "sensor.office_power"])

            store.grouping = .device
            check("sections start collapsed", !store.isExpanded("dev-Desk Lamp"))
            store.visibleSections = byDevice.map(\.id)
            store.expandAll()
            check("Expand All opens every section", byDevice.allSatisfy { store.isExpanded($0.id) })
            store.grouping = .area
            check("each grouping keeps its own open sections", !store.isExpanded("Office"))
            store.grouping = .device
            store.collapseAll()
            check("Collapse All closes every section", !byDevice.contains { store.isExpanded($0.id) })

            // S-030: Open at login shows the real registration, and tests never change it.
            let login = LoginItem.shared
            let before = SMAppService.mainApp.status
            check("Open at login shows the real registration",
                  login.isOn == (before == .enabled || before == .requiresApproval))
            login.set(!login.isOn)
            check("the self-test leaves login items alone", SMAppService.mainApp.status == before)

            // Check for Updates: the version comes from the bundle, and only a newer release is offered.
            let updater = Updater.shared
            let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            check("the running version comes from Info.plist", updater.current == AppVersion(bundled), bundled)
            let newer = AppVersion("\(updater.current.parts[0] + 1).0")!
            let reply = Data(#"{"tag_name":"v\#(newer)","html_url":"https://github.com/o/n/releases/tag/v\#(newer)"}"#.utf8)
            if case .available(let release) = UpdateCheck.outcome(current: updater.current, status: 200, body: reply, repo: "o/n") {
                check("a newer release is offered", release.version == newer)
            } else {
                check("a newer release is offered", false)
            }
            check("the running version isn't offered again",
                  UpdateCheck.outcome(current: newer, status: 200, body: reply, repo: "o/n") == .upToDate(newer))

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
