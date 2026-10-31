import Foundation

/// One Home Assistant entity as the last scan saw it, with its device and area.
public struct KnownEntity: Codable, Hashable, Sendable, Identifiable {
    public let entityID: String
    /// The friendly name Home Assistant shows.
    public let name: String
    public let deviceID: String?
    public let deviceName: String?
    public let areaName: String?

    public var id: String { entityID }

    public init(entityID: String, name: String, deviceID: String? = nil, deviceName: String? = nil, areaName: String? = nil) {
        self.entityID = entityID
        self.name = name
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.areaName = areaName
    }

    public var domain: String { EntityID(entityID)?.domain ?? "" }

    public var symbol: String { EntityID.symbol(forDomain: domain) }

    /// The name without the device's name in front, for a list already grouped
    /// by device: "Office Energy Meter Power" under "Office Energy Meter" -> "Power".
    public var nameWithinDevice: String {
        guard let deviceName, !deviceName.isEmpty,
              name.count > deviceName.count + 1,
              name.lowercased().hasPrefix(deviceName.lowercased() + " ")
        else { return name }
        return String(name.dropFirst(deviceName.count + 1))
    }

    /// True when every word of the query appears in the name, entity id,
    /// device, or area, ignoring case and accents.
    public func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = [name, entityID, deviceName ?? "", areaName ?? ""].joined(separator: " ")
        return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// How the entity list is split into sections.
public enum EntityGrouping: String, CaseIterable, Sendable, Identifiable {
    case device, area, type

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .device: "Device"
        case .area: "Area"
        case .type: "Type"
        }
    }
}

/// A titled run of entities in the list.
public struct EntitySection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let entities: [KnownEntity]
}

/// Every entity Home Assistant had at the last scan. Saved as JSON next to
/// the database, so the list is there without asking the server again.
public struct EntityCatalog: Codable, Equatable, Sendable {
    public var entities: [KnownEntity]
    /// The server the scan came from, so a different server triggers a new scan.
    public var server: String
    public var scannedAt: Date

    public init(entities: [KnownEntity], server: String, scannedAt: Date) {
        self.entities = entities
        self.server = server
        self.scannedAt = scannedAt
    }

    public var deviceCount: Int { Set(entities.compactMap(\.deviceID)).count }

    /// The entities that match the query, in sections sorted by title.
    /// Entities without a device or area come last.
    public func sections(by grouping: EntityGrouping, matching query: String = "") -> [EntitySection] {
        let found = entities.filter { $0.matches(query) }
        let groups = Dictionary(grouping: found) { entity -> String? in
            switch grouping {
            case .device: entity.deviceID
            case .area: entity.areaName
            case .type: entity.domain
            }
        }
        var sections = groups.compactMap { key, members -> EntitySection? in
            guard let key else { return nil }
            let title: String
            switch grouping {
            case .device: title = members.first?.deviceName ?? key
            case .area: title = key
            case .type: title = EntityID.domainTitle(key)
            }
            return EntitySection(id: key, title: title, entities: Self.sorted(members))
        }
        sections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if let loose = groups[nil] {
            let title = grouping == .device ? "No Device" : "No Area"
            sections.append(EntitySection(id: "", title: title, entities: Self.sorted(loose)))
        }
        return sections
    }

    private static func sorted(_ entities: [KnownEntity]) -> [KnownEntity] {
        entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Building from Home Assistant's answers

    struct State: Decodable {
        struct Attributes: Decodable { let friendly_name: String? }
        let entity_id: String
        let attributes: Attributes?
    }

    struct RegistryEntity: Decodable {
        let entity_id: String
        let device_id: String?
        let area_id: String?
    }

    struct Device: Decodable {
        let id: String
        let name: String?
        let name_by_user: String?
        let area_id: String?
    }

    struct Area: Decodable {
        let area_id: String
        let name: String
    }

    /// Joins `get_states` with the entity, device, and area registries. Each
    /// argument is the `result` JSON of one WebSocket command. Only entities
    /// with a state are listed; disabled ones have none.
    public static func build(states: Data, entityRegistry: Data, deviceRegistry: Data, areaRegistry: Data,
                             server: String, scannedAt: Date = .now) throws -> EntityCatalog {
        let decoder = JSONDecoder()
        let states = try decoder.decode([State].self, from: states)
        let registry = try decoder.decode([RegistryEntity].self, from: entityRegistry)
        let devices = try decoder.decode([Device].self, from: deviceRegistry)
        let areas = try decoder.decode([Area].self, from: areaRegistry)

        let entryByID = Dictionary(registry.map { ($0.entity_id, $0) }, uniquingKeysWith: { first, _ in first })
        let deviceByID = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let areaName = Dictionary(areas.map { ($0.area_id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let entities = states.map { state -> KnownEntity in
            let entry = entryByID[state.entity_id]
            let device = entry?.device_id.flatMap { deviceByID[$0] }
            // An entity's own area wins over its device's area, as in Home Assistant.
            let area = (entry?.area_id ?? device?.area_id).flatMap { areaName[$0] }
            let fallback = EntityID(state.entity_id)?.fallbackName ?? state.entity_id
            let name = state.attributes?.friendly_name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            return KnownEntity(entityID: state.entity_id, name: name, deviceID: device?.id,
                               deviceName: device.map { $0.name_by_user ?? $0.name ?? "Unnamed Device" },
                               areaName: area)
        }
        return EntityCatalog(entities: entities, server: server, scannedAt: scannedAt)
    }

    // MARK: Saving

    public static func load(from url: URL) -> EntityCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EntityCatalog.self, from: data)
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
