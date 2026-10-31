import Foundation
import Testing
@testable import HAAppKit

@Test("Values read like Home Assistant shows them", arguments: [
    (EntityState(entityID: "sensor.t", state: "21.4", unit: "°C"), "21.4 °C"),
    (EntityState(entityID: "sensor.p", state: "132", unit: "W"), "132 W"),
    (EntityState(entityID: "sensor.h", state: "48", unit: "%"), "48%"),
    (EntityState(entityID: "switch.tv", state: "on"), "On"),
    (EntityState(entityID: "remote.tv", state: "off"), "Off"),
    (EntityState(entityID: "sensor.p", state: "unavailable", unit: "W"), "—"),
    (EntityState(entityID: "light.a", state: "unknown"), "—"),
    (EntityState(entityID: "binary_sensor.door", state: "on", deviceClass: "door"), "Open"),
    (EntityState(entityID: "binary_sensor.motion", state: "off", deviceClass: "motion"), "Clear"),
    (EntityState(entityID: "binary_sensor.x", state: "on"), "On"),
    (EntityState(entityID: "sun.sun", state: "above_horizon"), "Above Horizon"),
    (EntityState(entityID: "sensor.v", state: "2026.10.1"), "2026.10.1"),
])
func displayValue(_ state: EntityState, expected: String) {
    #expect(state.displayValue == expected)
}

private func message(_ json: String) -> LiveMessage? {
    LiveMessage.parse(Data(json.utf8))
}

@Test func parsesHandshake() {
    #expect(message(#"{"type":"auth_required","ha_version":"2026.10"}"#) == .authRequired)
    #expect(message(#"{"type":"auth_ok"}"#) == .authOK)
    #expect(message(#"{"type":"auth_invalid","message":"bad"}"#) == .authInvalid)
    #expect(message("not json") == nil)
}

@Test func parsesStates() {
    let json = #"""
    {"id":1,"type":"result","success":true,"result":[
      {"entity_id":"sensor.tv_power","state":"85","attributes":{"friendly_name":"TV Power","unit_of_measurement":"W","device_class":"power"}},
      {"entity_id":"switch.tv","state":"on","attributes":{}}
    ]}
    """#
    #expect(message(json) == .states(id: 1, [
        EntityState(entityID: "sensor.tv_power", state: "85", friendlyName: "TV Power", unit: "W", deviceClass: "power"),
        EntityState(entityID: "switch.tv", state: "on"),
    ]))
}

@Test func parsesResults() {
    #expect(message(#"{"id":2,"type":"result","success":true,"result":null}"#) == .result(id: 2, success: true, error: nil))
    #expect(message(#"{"id":7,"type":"result","success":false,"error":{"code":"not_found","message":"Service not found."}}"#)
            == .result(id: 7, success: false, error: "Service not found."))
}

@Test func parsesStateChanges() {
    let changed = #"""
    {"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"switch.tv",
     "old_state":{"entity_id":"switch.tv","state":"off"},"new_state":{"entity_id":"switch.tv","state":"on","attributes":{"friendly_name":"TV"}}}}}
    """#
    #expect(message(changed) == .changed(entityID: "switch.tv", EntityState(entityID: "switch.tv", state: "on", friendlyName: "TV")))
    let removed = #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"switch.tv","new_state":null}}}"#
    #expect(message(removed) == .changed(entityID: "switch.tv", nil))
}

@Test func toggleTargetsTheEntity() throws {
    let request = LiveRequest.toggle(id: 9, entityID: try #require(EntityID("remote.living_room_tv")))
    #expect(request["domain"] as? String == "remote")
    #expect(request["service"] as? String == "toggle")
    #expect((request["target"] as? [String: String])?["entity_id"] == "remote.living_room_tv")
}
