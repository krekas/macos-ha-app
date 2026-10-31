import Foundation
import SwiftData
import HAAppKit

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with the groups and items from docs/STORIES.md. Seed only what a
/// person can create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        guard model.groups().isEmpty else { return }
        let living = model.addGroup(title: "Living Room")
        model.addItem(entityID: "light.living_room", to: living)
        model.addItem(entityID: "switch.tv_plug", to: living)
        model.addItem(entityID: "sensor.living_room_temperature", to: living)
        let office = model.addGroup(title: "Office")
        let desk = model.addItem(entityID: "light.desk_lamp", to: office)
        desk?.customName = "Desk"
        desk?.customSymbol = "lamp.desk"
        model.addItem(entityID: "sensor.office_power", to: office)
        try? model.context.save()
        model.entities.replace(with: sampleCatalog)
    }

    /// What a scan of the sample home finds (Settings > Entities).
    static var sampleCatalog: EntityCatalog {
        func entity(_ id: String, _ name: String, _ device: String? = nil, _ area: String? = nil) -> KnownEntity {
            KnownEntity(entityID: id, name: name, deviceID: device.map { "dev-\($0)" }, deviceName: device, areaName: area)
        }
        return EntityCatalog(entities: [
            entity("light.living_room", "Living Room Lamp", "Living Room Lamp", "Living Room"),
            entity("switch.tv_plug", "TV Plug", "TV Plug", "Living Room"),
            entity("sensor.tv_plug_power", "TV Plug Power", "TV Plug", "Living Room"),
            entity("sensor.living_room_temperature", "Living Room Climate Temperature", "Living Room Climate", "Living Room"),
            entity("sensor.living_room_humidity", "Living Room Climate Humidity", "Living Room Climate", "Living Room"),
            entity("binary_sensor.living_room_motion", "Living Room Climate Motion", "Living Room Climate", "Living Room"),
            entity("light.desk_lamp", "Desk Lamp", "Desk Lamp", "Office"),
            entity("sensor.office_power", "Office Energy Meter Power", "Office Energy Meter", "Office"),
            entity("sensor.office_energy", "Office Energy Meter Energy", "Office Energy Meter", "Office"),
            entity("sun.sun", "Sun"),
            entity("automation.lights_at_sunset", "Lights at Sunset"),
            entity("person.alex", "Alex"),
        ], server: "http://homeassistant.local:8123", scannedAt: .now.addingTimeInterval(-300))
    }
}
