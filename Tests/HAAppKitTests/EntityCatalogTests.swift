import Foundation
import Testing
@testable import HAAppKit

private func json(_ text: String) -> Data { Data(text.utf8) }

private func sample() throws -> EntityCatalog {
    try EntityCatalog.build(
        states: json("""
        [
          {"entity_id": "light.desk_lamp", "state": "on", "attributes": {"friendly_name": "Desk Lamp", "brightness": 200}},
          {"entity_id": "sensor.meter_power", "state": "132", "attributes": {"friendly_name": "Office Meter Power", "unit_of_measurement": "W"}},
          {"entity_id": "sensor.meter_energy", "state": "4.2", "attributes": {"friendly_name": "Office Meter Energy"}},
          {"entity_id": "sun.sun", "state": "above_horizon", "attributes": {}},
          {"entity_id": "switch.porch", "state": "off", "attributes": {"friendly_name": "Porch"}}
        ]
        """),
        entityRegistry: json("""
        [
          {"entity_id": "light.desk_lamp", "device_id": "d1", "area_id": null},
          {"entity_id": "sensor.meter_power", "device_id": "d2", "area_id": null},
          {"entity_id": "sensor.meter_energy", "device_id": "d2", "area_id": "kitchen"},
          {"entity_id": "switch.porch", "device_id": null, "area_id": "outside"},
          {"entity_id": "light.disabled", "device_id": "d1", "area_id": null}
        ]
        """),
        deviceRegistry: json("""
        [
          {"id": "d1", "name": "Hue Bulb 1", "name_by_user": "Desk Lamp", "area_id": "office"},
          {"id": "d2", "name": "Office Meter", "name_by_user": null, "area_id": "office"}
        ]
        """),
        areaRegistry: json("""
        [{"area_id": "office", "name": "Office"}, {"area_id": "kitchen", "name": "Kitchen"}, {"area_id": "outside", "name": "Outside"}]
        """),
        server: "http://ha.local:8123",
        scannedAt: Date(timeIntervalSince1970: 1_000_000.123))
}

@Test("A scan joins states with devices and areas")
func buildsCatalog() throws {
    let catalog = try sample()
    #expect(catalog.entities.count == 5)
    #expect(catalog.deviceCount == 2)
    let lamp = try #require(catalog.entities.first { $0.entityID == "light.desk_lamp" })
    #expect(lamp.deviceName == "Desk Lamp", "the user's device name wins")
    #expect(lamp.areaName == "Office", "the device's area")
    let energy = try #require(catalog.entities.first { $0.entityID == "sensor.meter_energy" })
    #expect(energy.areaName == "Kitchen", "the entity's own area wins over the device's")
    let sun = try #require(catalog.entities.first { $0.entityID == "sun.sun" })
    #expect(sun.name == "Sun", "no friendly name falls back to the object id")
    #expect(sun.deviceID == nil && sun.areaName == nil)
}

@Test("Group by device, entities without one last")
func groupsByDevice() throws {
    let sections = try sample().sections(by: .device)
    #expect(sections.map(\.title) == ["Desk Lamp", "Office Meter", "No Device"])
    #expect(sections[1].entities.map(\.name) == ["Office Meter Energy", "Office Meter Power"])
    #expect(sections[2].entities.map(\.entityID) == ["switch.porch", "sun.sun"])
}

@Test("Group by area and by type")
func groupsByAreaAndType() throws {
    let catalog = try sample()
    #expect(catalog.sections(by: .area).map(\.title) == ["Kitchen", "Office", "Outside", "No Area"])
    #expect(catalog.sections(by: .type).map(\.title) == ["Light", "Sensor", "Sun", "Switch"])
}

@Test("Search matches name, id, device, and area, every word, ignoring case")
func searches() throws {
    let catalog = try sample()
    func found(_ query: String) -> [String] {
        catalog.sections(by: .type, matching: query).flatMap(\.entities).map(\.entityID)
    }
    #expect(found("desk") == ["light.desk_lamp"])
    #expect(found("SENSOR.meter_p") == ["sensor.meter_power"])
    #expect(found("office power") == ["sensor.meter_power"])
    #expect(found("kitchen") == ["sensor.meter_energy"])
    #expect(found("nothing like this").isEmpty)
    #expect(found("  ").count == 5)
}

@Test("Names under a device header drop the device name")
func shortNames() {
    let power = KnownEntity(entityID: "sensor.p", name: "Office Meter Power", deviceID: "d", deviceName: "Office Meter")
    #expect(power.nameWithinDevice == "Power")
    let same = KnownEntity(entityID: "light.l", name: "Desk Lamp", deviceID: "d", deviceName: "Desk Lamp")
    #expect(same.nameWithinDevice == "Desk Lamp")
}

@Test("The catalog saves and loads")
func roundTrip() throws {
    let catalog = try sample()
    let url = FileManager.default.temporaryDirectory.appending(path: "catalog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try catalog.save(to: url)
    #expect(EntityCatalog.load(from: url) == catalog)
}

@Test("WebSocket messages keep their result as raw JSON")
func socketMessages() throws {
    let ok = try #require(SocketMessage(json(#"{"id": 2, "type": "result", "success": true, "result": [{"a": 1}]}"#)))
    #expect(ok.id == 2 && ok.success == true && ok.result != nil)
    let bad = try #require(SocketMessage(json(#"{"id": 3, "type": "result", "success": false, "error": {"code": "unauthorized", "message": "Unauthorized"}}"#)))
    #expect(bad.success == false && bad.errorMessage == "Unauthorized")
    #expect(SocketMessage(json("not json")) == nil)
}
