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
        switch entity?.domain {
        case "light": return "lightbulb"
        case "switch": return "powerplug"
        case "sensor": return "gauge"
        default: return "questionmark.circle"
        }
    }
}

/// App-wide state that the menu, Settings, and the self-test share.
@Observable
final class AppModel {
    let container: ModelContainer
    /// The server URL, access token, and connection status (Settings > General).
    let connection = Connection(persists: !Store.isOverridden)
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    var context: ModelContext { container.mainContext }

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
