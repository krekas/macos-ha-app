import HAAppKit
import SwiftData
import SwiftUI

/// What opens when you click the HAApp icon in the menu bar: the items
/// shown in the menu bar (Settings > Entities), by group.
struct MenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \MenuGroup.order) private var groups: [MenuGroup]

    var body: some View {
        VStack(spacing: 0) {
            let shown = groups.filter { $0.items.contains { $0.showInMenuBar } }
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No Items Yet", systemImage: "house")
                } description: {
                    Text("Choose what to show in Settings > Entities.")
                }
                .frame(maxWidth: .infinity, minHeight: Layout.menuEmptyHeight)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(shown) { group in
                            GroupSection(group: group)
                        }
                    }
                    .padding(Space.sm)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Layout.menuMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: Layout.menuWidth)
    }

    private var footer: some View {
        HStack {
            Button("Open HAApp") { AppDelegate.showMainWindow(openWindow) }
            .keyboardShortcut("0")
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Spacer()
            Button("Quit HAApp") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        // Borderless buttons draw their title in the tint: use the text shade,
        // so bright accents like Home Assistant blue stay readable.
        .tint(Palette.accentText)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}

private struct GroupSection: View {
    let group: MenuGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.sm)
            ForEach(group.sortedItems.filter(\.showInMenuBar)) { item in
                ItemRow(item: item)
            }
        }
    }
}

/// One item: its symbol, name, and live value. A light, switch, remote, or
/// other on/off entity shows a switch instead of its value: flip the switch,
/// or click anywhere on the row, to turn it on or off.
struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: MenuItem

    var body: some View {
        let name = model.name(of: item)
        let state = model.live.states[item.entityID]
        if item.entity?.isToggleable == true {
            let isOn = state?.isOn == true
            let canToggle = model.live.isLive && state != nil && state?.isUnavailable != true
            content(name: name, state: state, isOn: isOn) {
                Toggle(name, isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(Palette.accent)
            }
            .onTapGesture { if canToggle { toggle() } }
            .disabled(!canToggle)
            .help(help(name: name, state: state))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(value(state))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isOn ? "Turn Off" : "Turn On")
            .accessibilityAction { if canToggle { toggle() } }
        } else {
            content(name: name, state: state, isOn: false) {
                Text(value(state))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Motion.numberRoll, value: state?.displayValue)
            }
            .help(help(name: name, state: state))
            .accessibilityElement(children: .combine)
        }
    }

    private func toggle() {
        withAnimation(Motion.quick) { model.live.toggle(item.entityID) }
    }

    private func content(name: String, state: EntityState?, isOn: Bool,
                         @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol(state))
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: Layout.symbolColumn)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.sm)
            if model.live.errors[item.entityID] != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            trailing()
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .opacity(isMissing(state) ? 0.5 : 1)
    }

    /// Live and connected, but Home Assistant has no such entity.
    private func isMissing(_ state: EntityState?) -> Bool {
        state == nil && model.live.isLive
    }

    private func symbol(_ state: EntityState?) -> String {
        isMissing(state) && item.customSymbol == nil ? "questionmark.circle" : item.symbol
    }

    private func value(_ state: EntityState?) -> String {
        if let state { return state.displayValue }
        return isMissing(state) ? "Not found" : "—"
    }

    private func help(name: String, state: EntityState?) -> String {
        if let error = model.live.errors[item.entityID] {
            return "Couldn't turn \(state?.isOn == true ? "off" : "on") \(name): \(error)"
        }
        if isMissing(state) { return "\(item.entityID) isn't in Home Assistant anymore." }
        if state?.isUnavailable == true { return "Home Assistant reports \(name) as unavailable." }
        guard model.live.isLive else { return "\(item.entityID): not connected to Home Assistant" }
        if item.entity?.isToggleable == true { return state?.isOn == true ? "Turn off \(name)" : "Turn on \(name)" }
        return item.entityID
    }
}
