import Testing
@testable import HAAppKit

@Test("Parse entity ids", arguments: [
    ("light.desk_lamp", "light", "desk_lamp"),
    ("  Switch.TV_Plug \n", "switch", "tv_plug"),
    ("sensor.office.power", "sensor", "office.power"),
])
func parses(_ input: String, domain: String, object: String) throws {
    let id = try #require(EntityID(input))
    #expect(id.domain == domain)
    #expect(id.objectID == object)
    #expect(id.description == "\(domain).\(object)")
}

@Test("Reject malformed entity ids", arguments: ["", "light", "light.", ".desk", "   "])
func rejects(_ input: String) {
    #expect(EntityID(input) == nil)
}

@Test func fallbackName() {
    #expect(EntityID("light.living_room_ceiling")?.fallbackName == "Living Room Ceiling")
}

@Test func domains() {
    #expect(EntityID("light.a")?.isToggleable == true)
    #expect(EntityID("switch.a")?.isToggleable == true)
    #expect(EntityID("sensor.a")?.isToggleable == false)
    #expect(EntityID("sensor.a")?.isSupported == true)
    #expect(EntityID("climate.a")?.isSupported == false)
}
