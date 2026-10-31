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
        model.entities.replace(with: sampleCatalog)
        model.live.preview(sampleStates)
        // Shown the way Settings > Entities shows them: groups follow areas.
        func show(_ id: String, _ name: String = "", menuBar: Bool = true, window: Bool = true) {
            var draft = model.draft(for: id, turningOn: .menuBar)
            draft.name = name
            draft.showInMenuBar = menuBar
            draft.showInWindow = window
            model.save(draft)
        }
        show("light.living_room")
        show("remote.living_room_tv", "TV")
        show("sensor.tv_plug_power", "TV Power")
        show("sensor.living_room_temperature", "Temperature")
        show("light.desk_lamp", "Desk", menuBar: false)
        show("sensor.office_power", window: false)
        // One open section, so snapshots show both states.
        model.entities.setExpanded("dev-Desk Lamp", true)
    }

    /// What a scan of the sample home finds (Settings > Entities).
    static var sampleCatalog: EntityCatalog {
        func entity(_ id: String, _ name: String, _ device: String? = nil, _ area: String? = nil) -> KnownEntity {
            KnownEntity(entityID: id, name: name, deviceID: device.map { "dev-\($0)" }, deviceName: device, areaName: area)
        }
        return EntityCatalog(entities: [
            entity("light.living_room", "Living Room Lamp", "Living Room Lamp", "Living Room"),
            entity("switch.tv_plug", "TV Plug", "TV Plug", "Living Room"),
            entity("remote.living_room_tv", "Living Room TV", "Living Room TV", "Living Room"),
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

    /// What Home Assistant reports for the sample home right now.
    static var sampleStates: [EntityState] {
        [
            EntityState(entityID: "light.living_room", state: "on", friendlyName: "Living Room Lamp"),
            EntityState(entityID: "switch.tv_plug", state: "on", friendlyName: "TV Plug"),
            EntityState(entityID: "remote.living_room_tv", state: "on", friendlyName: "Living Room TV"),
            EntityState(entityID: "sensor.tv_plug_power", state: "85.2", friendlyName: "TV Plug Power", unit: "W", deviceClass: "power"),
            EntityState(entityID: "sensor.living_room_temperature", state: "21.4", friendlyName: "Living Room Climate Temperature",
                        unit: "°C", deviceClass: "temperature"),
            EntityState(entityID: "sensor.living_room_humidity", state: "48", friendlyName: "Living Room Climate Humidity",
                        unit: "%", deviceClass: "humidity"),
            EntityState(entityID: "binary_sensor.living_room_motion", state: "off", friendlyName: "Living Room Climate Motion",
                        deviceClass: "motion"),
            EntityState(entityID: "light.desk_lamp", state: "off", friendlyName: "Desk Lamp"),
            EntityState(entityID: "sensor.office_power", state: "132", friendlyName: "Office Energy Meter Power", unit: "W", deviceClass: "power"),
            EntityState(entityID: "sensor.office_energy", state: "4.21", friendlyName: "Office Energy Meter Energy", unit: "kWh"),
            EntityState(entityID: "sun.sun", state: "above_horizon", friendlyName: "Sun"),
            EntityState(entityID: "automation.lights_at_sunset", state: "on", friendlyName: "Lights at Sunset"),
            EntityState(entityID: "person.alex", state: "home", friendlyName: "Alex"),
        ]
    }
}
