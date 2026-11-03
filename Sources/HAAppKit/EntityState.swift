import Foundation

/// One entity's live state from Home Assistant: `get_states` and every
/// `state_changed` event. Kept in memory only, never saved.
public struct EntityState: Equatable, Sendable {
    public let entityID: String
    public var state: String
    public var friendlyName: String?
    public var unit: String?
    public var deviceClass: String?

    public init(entityID: String, state: String, friendlyName: String? = nil, unit: String? = nil, deviceClass: String? = nil) {
        self.entityID = entityID
        self.state = state
        self.friendlyName = friendlyName
        self.unit = unit
        self.deviceClass = deviceClass
    }

    /// Reads one state object: `{"entity_id", "state", "attributes": {…}}`.
    init?(json: [String: Any]) {
        guard let id = json["entity_id"] as? String, let state = json["state"] as? String else { return nil }
        let attributes = json["attributes"] as? [String: Any] ?? [:]
        func text(_ key: String) -> String? {
            (attributes[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        self.init(entityID: id, state: state, friendlyName: text("friendly_name"),
                  unit: text("unit_of_measurement"), deviceClass: text("device_class"))
    }

    public var domain: String { EntityID(entityID)?.domain ?? "" }

    /// Home Assistant has no value for it right now.
    public var isUnavailable: Bool { state == "unavailable" || state == "unknown" }

    public var isOn: Bool { state == "on" }

    /// What a row shows on its trailing side: "21.4 °C", "On", "Detected", or "—".
    public var displayValue: String {
        if isUnavailable || state.isEmpty { return "—" }
        if domain == "binary_sensor" { return Self.binaryWord(on: isOn, deviceClass: deviceClass) }
        switch state {
        case "on": return "On"
        case "off": return "Off"
        default: break
        }
        if let unit {
            return unit == "%" ? "\(state)%" : "\(state) \(unit)"
        }
        // Words like "above_horizon" or "not_home" read better as "Above Horizon".
        if state.allSatisfy({ $0.isLowercase || $0 == "_" }) {
            return EntityID.domainTitle(state)
        }
        return state
    }

    /// Binary sensors say what they sense: a door is Open, motion is Detected.
    static func binaryWord(on: Bool, deviceClass: String?) -> String {
        switch deviceClass {
        case "door", "window", "opening", "garage_door": on ? "Open" : "Closed"
        case "motion", "occupancy", "presence", "moving", "sound", "vibration", "smoke", "gas", "moisture", "tamper":
            on ? "Detected" : "Clear"
        case "connectivity": on ? "Connected" : "Disconnected"
        case "plug": on ? "Plugged In" : "Unplugged"
        case "lock": on ? "Unlocked" : "Locked"
        case "battery": on ? "Low" : "Normal"
        case "problem": on ? "Problem" : "OK"
        default: on ? "On" : "Off"
        }
    }
}

/// One message from Home Assistant's WebSocket API, as the live feed needs it.
public enum LiveMessage: Equatable, Sendable {
    case authRequired
    case authOK
    case authInvalid
    case pong(id: Int)
    /// The answer to `get_states`: every entity's state.
    case states(id: Int, [EntityState])
    /// A `state_changed` event. A nil state means the entity was removed.
    case changed(entityID: String, EntityState?)
    /// The answer to any other command, like `call_service`.
    case result(id: Int, success: Bool, error: String?)
    case other

    public static func parse(_ data: Data) -> LiveMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "auth_required": return .authRequired
        case "auth_ok": return .authOK
        case "auth_invalid": return .authInvalid
        case "pong":
            guard let id = json["id"] as? Int else { return .other }
            return .pong(id: id)
        case "result":
            guard let id = json["id"] as? Int else { return .other }
            let success = json["success"] as? Bool ?? false
            if success, let list = json["result"] as? [[String: Any]], list.isEmpty || list.first?["entity_id"] != nil {
                return .states(id: id, list.compactMap(EntityState.init(json:)))
            }
            let error = (json["error"] as? [String: Any])?["message"] as? String
            return .result(id: id, success: success, error: error)
        case "event":
            guard let event = json["event"] as? [String: Any],
                  event["event_type"] as? String == "state_changed",
                  let data = event["data"] as? [String: Any],
                  let id = data["entity_id"] as? String
            else { return .other }
            return .changed(entityID: id, (data["new_state"] as? [String: Any]).flatMap(EntityState.init(json:)))
        default:
            return .other
        }
    }
}

/// Messages HAApp sends over the live WebSocket.
public enum LiveRequest {
    public static func ping(id: Int) -> [String: Any] {
        ["id": id, "type": "ping"]
    }

    public static func auth(token: String) -> [String: Any] {
        ["type": "auth", "access_token": token]
    }

    public static func getStates(id: Int) -> [String: Any] {
        ["id": id, "type": "get_states"]
    }

    public static func subscribeStateChanges(id: Int) -> [String: Any] {
        ["id": id, "type": "subscribe_events", "event_type": "state_changed"]
    }

    /// Turns a light, switch, remote, or other on/off entity on or off.
    public static func toggle(id: Int, entityID: EntityID) -> [String: Any] {
        ["id": id, "type": "call_service", "domain": entityID.domain, "service": "toggle",
         "target": ["entity_id": entityID.description]]
    }
}
