import Foundation
import SwiftData

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
    }
}
