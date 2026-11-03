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
            check("a scan is saved next to the database", EntityCatalog.load(from: store.url)?.entities.count == 13)
            let reloaded = EntityStore(url: store.url)
            check("the saved list loads at launch", reloaded.catalog == store.catalog)
            if let sample = ServerURL("http://homeassistant.local:8123"), let other = ServerURL("http://10.0.0.2:8123") {
                check("the same server needs no new scan", !store.needsScan(for: sample))
                check("another server needs a new scan", store.needsScan(for: other))
            }
            if let dead = ServerURL("http://127.0.0.1:9") {
                await store.scan(server: dead, token: "x")
                check("a failed scan keeps the last list", store.catalog?.entities.count == 13)
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

            // S-015: show entities in the menu bar, the window, or both, with a name.
            let live = model.live
            live.preview(SeedData.sampleStates)
            let tvDraft = model.draft(for: "remote.living_room_tv", turningOn: .menuBar)
            check("the first toggle opens a new draft for that place",
                  tvDraft.isNew && tvDraft.showInMenuBar && !tvDraft.showInWindow && tvDraft.name.isEmpty)
            check("the draft offers Home Assistant's name", tvDraft.homeAssistantName == "Living Room TV")
            var named = tvDraft
            named.name = "  TV "
            let tv = model.save(named)
            check("a saved draft is an item with a trimmed name", tv?.customName == "TV" && tv.map(model.name(of:)) == "TV")
            check("a new item goes in its area's group", tv?.group?.title == "Living Room")
            check("it shows only where it was turned on", tv?.showInMenuBar == true && tv?.showInWindow == false)
            model.setShown("remote.living_room_tv", in: .window, true)
            check("the second toggle just shows it", tv?.showInWindow == true && !model.draft(for: "remote.living_room_tv").isNew)
            model.setShown("remote.living_room_tv", in: .menuBar, false)
            model.setShown("remote.living_room_tv", in: .window, false)
            check("hidden everywhere keeps the item and its name", model.item(for: "remote.living_room_tv")?.customName == "TV")
            check("shown again, it asks for a name again", model.draft(for: "remote.living_room_tv", turningOn: .window).isNew)
            var blank = model.draft(for: "sensor.tv_plug_power", turningOn: .window)
            blank.name = " "
            if let power = model.save(blank) {
                check("a blank name uses Home Assistant's", power.customName == nil && model.name(of: power) == "TV Plug Power")
                check("a sensor shows its value and unit", live.states[power.entityID]?.displayValue == "85.2 W")
            }
            if let loose = model.save(model.draft(for: "sun.sun", turningOn: .window)) {
                check("an entity with no area goes in Other", loose.group?.title == "Other")
            }
            // A remote turns on and off like a switch.
            live.toggle("remote.living_room_tv")
            check("toggling a remote flips it", live.states["remote.living_room_tv"]?.isOn == false)
            live.toggle("sensor.tv_plug_power")
            check("a sensor can't be toggled", live.states["sensor.tv_plug_power"]?.state == "85.2")
            live.stop()
            await checkLiveFeed()

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

    private static func checkLiveFeed() async {
        let server = ServerURL("http://127.0.0.1:8123")!
        let socket = ScriptedLiveSocket()
        let live = LiveStates(makeSocket: { _ in socket })
        defer { live.stop() }
        live.start(server: server, token: "test")
        socket.push(.authOK)
        await waitUntil { !socket.sent.isEmpty }
        check("live feed subscribes before requesting initial values",
              socket.sent.first?["type"] as? String == "subscribe_events"
              && !socket.sent.contains { $0["type"] as? String == "get_states" })
        socket.push(.result(id: 1, success: true, error: nil))
        await waitUntil { socket.sent.contains { $0["type"] as? String == "get_states" } }
        let initial = EntityState(entityID: "sensor.power", state: "10")
        socket.push(.states(id: 2, [initial]))
        await waitUntil { live.isLive }
        socket.push(.changed(entityID: initial.entityID, EntityState(entityID: initial.entityID, state: "20")))
        await waitUntil { live.states[initial.entityID]?.state == "20" }
        check("live events replace the initial value", live.states[initial.entityID]?.state == "20")
        live.stop()
        await waitUntil { socket.cancelled }

        let rejected = ScriptedLiveSocket()
        let failed = LiveStates(makeSocket: { _ in rejected })
        defer { failed.stop() }
        failed.start(server: server, token: "test")
        rejected.push(.authOK)
        rejected.push(.result(id: 1, success: false, error: "Subscription failed"))
        await waitUntil { rejected.cancelled }
        check("a rejected subscription closes the connection for retry", rejected.cancelled && !failed.isLive)

        let stalled = ScriptedLiveSocket()
        let replacement = ScriptedLiveSocket()
        var connections = 0
        let recovering = LiveStates(heartbeatInterval: .milliseconds(20), responseTimeout: .milliseconds(40)) { _ in
            connections += 1
            return connections == 1 ? stalled : replacement
        }
        defer { recovering.stop() }
        recovering.start(server: server, token: "test")
        stalled.push(.authOK)
        stalled.push(.result(id: 1, success: true, error: nil))
        stalled.push(.states(id: 2, [initial]))
        await waitUntil { stalled.sent.contains { $0["type"] as? String == "ping" } }
        if let ping = stalled.sent.last?["id"] as? Int { stalled.push(.pong(id: ping)) }
        await waitUntil { stalled.sent.filter { $0["type"] as? String == "ping" }.count >= 2 }
        check("an idle connection stays live when heartbeat replies arrive", recovering.isLive && !stalled.cancelled)
        // Events cannot substitute for the matching pong.
        stalled.push(.changed(entityID: initial.entityID, initial))
        stalled.push(.pong(id: -1))
        await waitUntil { stalled.cancelled && !recovering.isLive }
        check("a missing heartbeat closes a stalled connection", stalled.cancelled && !recovering.isLive)
        await waitUntil { connections >= 2 }
        replacement.push(.authOK)
        replacement.push(.result(id: 1, success: true, error: nil))
        replacement.push(.states(id: 2, [EntityState(entityID: initial.entityID, state: "30")]))
        await waitUntil { recovering.states[initial.entityID]?.state == "30" }
        check("reconnecting fetches fresh values", connections >= 2 && recovering.isLive
              && recovering.states[initial.entityID]?.state == "30")
        recovering.stop()

        let silent = ScriptedLiveSocket()
        let starting = LiveStates(heartbeatInterval: .milliseconds(20), responseTimeout: .milliseconds(40)) { _ in silent }
        defer { starting.stop() }
        starting.start(server: server, token: "test")
        await waitUntil { silent.cancelled }
        check("a silent handshake times out", silent.cancelled && !starting.isLive)

        let obsolete = ScriptedLiveSocket(finishesOnCancel: false)
        let current = ScriptedLiveSocket()
        var starts = 0
        let restarting = LiveStates { _ in
            starts += 1
            return starts == 1 ? obsolete : current
        }
        defer { restarting.stop() }
        restarting.start(server: server, token: "test")
        obsolete.push(.authOK)
        await waitUntil { !obsolete.sent.isEmpty }
        restarting.start(server: server, token: "test")
        current.push(.authOK)
        current.push(.result(id: 1, success: true, error: nil))
        current.push(.states(id: 2, [initial]))
        await waitUntil { restarting.isLive }
        obsolete.push(.states(id: 2, [EntityState(entityID: initial.entityID, state: "obsolete")]))
        // Let the cancelled receive resume after its replacement is live.
        await Task.yield()
        await Task.yield()
        check("a replaced socket cannot overwrite values or mark the new feed offline",
              restarting.isLive && restarting.states[initial.entityID] == initial)
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

/// Exercises the actual feed loop without a server or the user's credentials.
private final class ScriptedLiveSocket: LiveSocket {
    private var messages: [LiveMessage] = []
    private var waiting: CheckedContinuation<LiveMessage?, Error>?
    private(set) var sent: [[String: Any]] = []
    private(set) var cancelled = false
    private let finishesOnCancel: Bool

    init(finishesOnCancel: Bool = true) { self.finishesOnCancel = finishesOnCancel }

    func push(_ message: LiveMessage) {
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: message)
        } else {
            messages.append(message)
        }
    }
    func send(_ object: [String: Any]) async throws { sent.append(object) }
    func receive() async throws -> LiveMessage? {
        if cancelled { throw CancellationError() }
        if !messages.isEmpty { return messages.removeFirst() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func cancel() {
        cancelled = true
        guard finishesOnCancel else { return }
        waiting?.resume(throwing: CancellationError())
        waiting = nil
    }
}
