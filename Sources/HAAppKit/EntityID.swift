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

    /// Domains whose entities turn on and off with the `toggle` service.
    /// A TV usually has two: `switch.tv` (a smart plug cuts its power) and
    /// `remote.living_room_tv` (the TV itself), and both work the same way.
    public static let toggleableDomains: Set<String> = [
        "light", "switch", "remote", "input_boolean", "fan", "automation", "siren", "humidifier",
    ]

    /// Clicking the item turns it on or off. Everything else shows its value.
    public var isToggleable: Bool { Self.toggleableDomains.contains(domain) }

    /// "binary_sensor" -> "Binary Sensor", for section titles.
    public static func domainTitle(_ domain: String) -> String {
        domain.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The SF Symbol for an entity of this domain.
    public static func symbol(forDomain domain: String) -> String {
        switch domain {
        case "light": "lightbulb"
        case "switch": "powerplug"
        case "remote": "appletvremote.gen4"
        case "siren": "light.beacon.max"
        case "humidifier": "humidifier"
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
