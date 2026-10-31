import HAAppKit
import SwiftUI

/// What a menu row and a window tile show for one item: its name, symbol,
/// live value, and whether a click turns it on or off.
@MainActor
struct ItemStatus {
    let item: MenuItem
    let model: AppModel
    let name: String
    let state: EntityState?

    init(item: MenuItem, model: AppModel) {
        self.item = item
        self.model = model
        name = model.name(of: item)
        state = model.live.states[item.entityID]
    }

    /// A light, switch, remote, or other on/off entity.
    var isToggleable: Bool { item.entity?.isToggleable == true }
    var isOn: Bool { isToggleable && state?.isOn == true }
    var canToggle: Bool { isToggleable && model.live.isLive && state != nil && state?.isUnavailable != true }
    var error: String? { model.live.errors[item.entityID] }

    /// Live and connected, but Home Assistant has no such entity.
    var isMissing: Bool { state == nil && model.live.isLive }
    var isUnavailable: Bool { state?.isUnavailable == true }

    var symbol: String {
        isMissing && item.customSymbol == nil ? "questionmark.circle" : item.symbol
    }

    var value: String {
        if let state { return state.displayValue }
        return isMissing ? "Not found" : "—"
    }

    var help: String {
        if let error { return "Couldn't turn \(state?.isOn == true ? "off" : "on") \(name): \(error)" }
        if isMissing { return "\(item.entityID) isn't in Home Assistant anymore." }
        if isUnavailable { return "Home Assistant reports \(name) as unavailable." }
        guard model.live.isLive else { return "\(item.entityID): not connected to Home Assistant" }
        if isToggleable { return isOn ? "Turn off \(name)" : "Turn on \(name)" }
        return item.entityID
    }

    func toggle() {
        guard canToggle else { return }
        withAnimation(Motion.quick) { model.live.toggle(item.entityID) }
    }
}

extension View {
    /// One accessible button for an on/off item: its name, value, and Turn On or Turn Off.
    func itemToggleAccessibility(_ status: ItemStatus) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(status.name)
            .accessibilityValue(status.value)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(status.isOn ? "Turn Off" : "Turn On")
            .accessibilityAction { status.toggle() }
    }
}
