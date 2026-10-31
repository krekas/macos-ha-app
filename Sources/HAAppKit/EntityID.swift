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
}
