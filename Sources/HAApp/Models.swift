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

    init(entityID: String, order: Int, group: MenuGroup? = nil) {
        self.entityID = entityID
        self.order = order
        self.group = group
    }

    var entity: EntityID? { EntityID(entityID) }

    /// The name the menu shows. The friendly name from Home Assistant comes in a later story.
    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        return entity?.fallbackName ?? entityID
    }

    var symbol: String {
        if let customSymbol, !customSymbol.isEmpty { return customSymbol }
        guard let domain = entity?.domain else { return "questionmark.circle" }
        return EntityID.symbol(forDomain: domain)
    }
}

/// App-wide state that the menu, Settings, and the self-test share.
@Observable
final class AppModel {
    let container: ModelContainer
    /// The server URL, access token, and connection status (Settings > General).
    let connection = Connection(persists: !Store.isOverridden)
    /// Every entity from the last scan (Settings > Entities).
    let entities = EntityStore(url: Store.entitiesURL)
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
        if connection.isConnected { await rescanEntities() }
    }

    /// At launch: check the saved connection, and scan only when there's no
    /// list yet or it came from another server.
    func checkSaved() async {
        guard connection.hasSavedToken else { return }
        await connection.connect()
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
}
