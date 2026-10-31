import Foundation

/// A Home Assistant entity id like `light.desk_lamp`: a domain, a dot, and an object id.
public struct EntityID: Hashable, Sendable, CustomStringConvertible {
    public let domain: String
    public let objectID: String

    /// Parses `domain.object_id`. Returns nil when either part is missing.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let dot = trimmed.firstIndex(of: "."),
              dot != trimmed.startIndex,
              trimmed.index(after: dot) != trimmed.endIndex
        else { return nil }
        domain = String(trimmed[..<dot])
        objectID = String(trimmed[trimmed.index(after: dot)...])
    }

    public var description: String { "\(domain).\(objectID)" }

    /// A readable name from the object id, for when Home Assistant has no
    /// friendly name: `desk_lamp` -> "Desk Lamp".
    public var fallbackName: String {
        objectID.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Domains the menu supports in version one.
    public static let supportedDomains: Set<String> = ["light", "switch", "sensor"]

    public var isSupported: Bool { Self.supportedDomains.contains(domain) }

    /// Lights and switches turn on and off; sensors are read-only.
    public var isToggleable: Bool { domain == "light" || domain == "switch" }

    /// "binary_sensor" -> "Binary Sensor", for section titles.
    public static func domainTitle(_ domain: String) -> String {
        domain.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The SF Symbol for an entity of this domain.
    public static func symbol(forDomain domain: String) -> String {
        switch domain {
        case "light": "lightbulb"
        case "switch": "powerplug"
        case "sensor": "gauge"
        case "binary_sensor": "dot.radiowaves.left.and.right"
        case "climate": "thermometer.medium"
        case "cover": "blinds.vertical.closed"
        case "fan": "fan"
        case "lock": "lock"
        case "media_player": "play.rectangle"
        case "camera": "video"
        case "person": "person"
        case "device_tracker": "location"
        case "zone": "mappin.and.ellipse"
        case "automation": "gearshape.2"
        case "script": "scroll"
        case "scene": "theatermasks"
        case "button", "input_button": "button.programmable"
        case "input_boolean": "switch.2"
        case "number", "input_number": "number"
        case "select", "input_select": "list.bullet"
        case "input_text", "text": "character.cursor.ibeam"
        case "update": "arrow.down.circle"
        case "sun": "sun.max"
        case "weather": "cloud.sun"
        default: "circle.dashed"
        }
    }
}
