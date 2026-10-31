import Foundation
import SwiftData
import HAAppKit

/// A titled section of items in the menu.
@Model
final class MenuGroup {
    var title: String
    var order: Int
    var isCollapsed: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \MenuItem.group)
    var items: [MenuItem] = []
    /// A stable id for links, sync, and the agent CLI.
    var uuid: UUID = UUID()

    init(title: String, order: Int) {
        self.title = title
        self.order = order
    }

    var sortedItems: [MenuItem] { items.sorted { $0.order < $1.order } }
}

/// One Home Assistant entity added to the menu.
@Model
final class MenuItem {
    /// The Home Assistant entity id, like `light.desk_lamp`.
    var entityID: String
    /// Shown instead of the friendly name when set.
    var customName: String?
    /// An SF Symbol shown instead of the default for the domain.
    var customSymbol: String?
    var order: Int
    var group: MenuGroup?
    var uuid: UUID = UUID()
    /// Where the item shows. Both off keeps the item, and its name, for later.
    var showInMenuBar: Bool = true
    var showInWindow: Bool = true

    init(entityID: String, order: Int, group: MenuGroup? = nil) {
        self.entityID = entityID
        self.order = order
        self.group = group
    }

    var entity: EntityID? { EntityID(entityID) }

    /// The custom name, or nil when it's blank.
    var givenName: String? {
        guard let name = customName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// The custom name, or a name made from the entity id. Views use
    /// `AppModel.name(of:)`, which knows Home Assistant's friendly name.
    var displayName: String {
        givenName ?? entity?.fallbackName ?? entityID
    }

    func isShown(in place: Place) -> Bool {
        switch place {
        case .menuBar: showInMenuBar
        case .window: showInWindow
        }
    }

    var isShownAnywhere: Bool { showInMenuBar || showInWindow }

    var symbol: String {
        if let customSymbol, !customSymbol.isEmpty { return customSymbol }
        guard let domain = entity?.domain else { return "questionmark.circle" }
        return EntityID.symbol(forDomain: domain)
    }
}

/// Where an item can show: the menu bar menu, the main window, or both.
enum Place: String, CaseIterable, Identifiable {
    case menuBar
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Menu Bar"
        case .window: "Window"
        }
    }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .window: "macwindow"
        }
    }
}

/// What the naming sheet edits before it's saved to an item.
struct ItemDraft: Identifiable {
    let entityID: String
    /// Home Assistant's name, shown as the placeholder and used when the name is blank.
    let homeAssistantName: String
    var name: String
    var showInMenuBar: Bool
    var showInWindow: Bool
    /// True when the entity isn't shown anywhere yet.
    let isNew: Bool

    var id: String { entityID }
}

/// App-wide state that the menu, Settings, and the self-test share.
@Observable
final class AppModel {
    let container: ModelContainer
    /// The server URL, access token, and connection status (Settings > General).
    let connection = Connection(persists: !Store.isOverridden)
    /// Every entity from the last scan (Settings > Entities).
    let entities = EntityStore(url: Store.entitiesURL)
    /// Live states from Home Assistant, while connected.
    let live = LiveStates()
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    var context: ModelContext { container.mainContext }

    /// Connect in Settings > General. A successful Connect always scans the
    /// entities, since the server or its entities may have changed.
    func connect() async {
        await connection.connect()
        startLive()
        if connection.isConnected { await rescanEntities() }
    }

    /// Disconnect in Settings > General: forgets the token and closes the live feed.
    func disconnect() {
        connection.disconnect()
        live.stop()
    }

    private func startLive() {
        if connection.isConnected, let server = connection.server {
            live.start(server: server, token: connection.tokenText)
        } else {
            live.stop()
        }
    }

    /// At launch: check the saved connection, and scan only when there's no
    /// list yet or it came from another server.
    func checkSaved() async {
        guard connection.hasSavedToken else { return }
        await connection.connect()
        startLive()
        if connection.isConnected, let server = connection.server, entities.needsScan(for: server) {
            await rescanEntities()
        }
    }

    var canRescan: Bool { connection.isConnected && !entities.isScanning }

    /// Reads the whole entity list from Home Assistant again.
    func rescanEntities() async {
        guard connection.isConnected, let server = connection.server else { return }
        await entities.scan(server: server, token: connection.tokenText)
    }

    func groups() -> [MenuGroup] {
        (try? context.fetch(FetchDescriptor<MenuGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    func addGroup(title: String) -> MenuGroup {
        let group = MenuGroup(title: title, order: (groups().map(\.order).max() ?? -1) + 1)
        context.insert(group)
        return group
    }

    /// Adds an entity to the end of a group. Returns nil for a malformed entity id.
    @discardableResult
    func addItem(entityID: String, to group: MenuGroup?) -> MenuItem? {
        guard let id = EntityID(entityID) else { return nil }
        let order = (group?.items.map(\.order).max() ?? -1) + 1
        let item = MenuItem(entityID: id.description, order: order, group: group)
        context.insert(item)
        return item
    }

    func remove(_ item: MenuItem) {
        context.delete(item)
    }

    // MARK: Showing entities

    /// The item for an entity, shown or not.
    func item(for entityID: String) -> MenuItem? {
        var descriptor = FetchDescriptor<MenuItem>(predicate: #Predicate { $0.entityID == entityID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// The name Home Assistant gives an entity: the live friendly name, then
    /// the scanned name, then one made from the entity id.
    func homeAssistantName(of entityID: String) -> String {
        live.states[entityID]?.friendlyName
            ?? entities.entity(entityID)?.name
            ?? EntityID(entityID)?.fallbackName
            ?? entityID
    }

    /// The name an item shows: the user's name, or Home Assistant's when blank.
    func name(of item: MenuItem) -> String {
        item.givenName ?? homeAssistantName(of: item.entityID)
    }

    /// A draft for the naming sheet. `turningOn` is the place whose toggle
    /// was just switched on, for an entity that isn't shown anywhere yet.
    func draft(for entityID: String, turningOn place: Place? = nil) -> ItemDraft {
        let item = item(for: entityID)
        let isNew = !(item?.isShownAnywhere ?? false)
        return ItemDraft(entityID: entityID,
                         homeAssistantName: homeAssistantName(of: entityID),
                         name: item?.givenName ?? "",
                         showInMenuBar: isNew ? place == .menuBar : item?.showInMenuBar ?? false,
                         showInWindow: isNew ? place == .window : item?.showInWindow ?? false,
                         isNew: isNew)
    }

    /// Saves the naming sheet. A new item goes last in the group named after
    /// the entity's area, or in "Other" when it has none.
    @discardableResult
    func save(_ draft: ItemDraft) -> MenuItem? {
        let item = item(for: draft.entityID) ?? addItem(entityID: draft.entityID, to: group(forArea: draft.entityID))
        guard let item else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        item.customName = name.isEmpty ? nil : name
        item.showInMenuBar = draft.showInMenuBar
        item.showInWindow = draft.showInWindow
        try? context.save()
        return item
    }

    /// Shows or hides an entity in one place. Hiding keeps the item and its name.
    func setShown(_ entityID: String, in place: Place, _ shown: Bool) {
        guard let item = item(for: entityID) else {
            if shown { save(draft(for: entityID, turningOn: place)) }
            return
        }
        switch place {
        case .menuBar: item.showInMenuBar = shown
        case .window: item.showInWindow = shown
        }
        try? context.save()
    }

    private func group(forArea entityID: String) -> MenuGroup {
        let title = entities.entity(entityID)?.areaName ?? "Other"
        return groups().first { $0.title == title } ?? addGroup(title: title)
    }
}
