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
        let status = ItemStatus(item: item, model: model)
        if status.isToggleable {
            content(status) {
                Toggle(status.name, isOn: Binding(get: { status.isOn }, set: { _ in status.toggle() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(Palette.accent)
            }
            .onTapGesture { status.toggle() }
            .disabled(!status.canToggle)
            .help(status.help)
            .itemToggleAccessibility(status)
        } else {
            content(status) {
                Text(status.value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Motion.numberRoll, value: status.value)
            }
            .help(status.help)
            .accessibilityElement(children: .combine)
        }
    }

    private func content(_ status: ItemStatus, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: status.symbol)
                .symbolVariant(status.isOn ? .fill : .none)
                .foregroundStyle(status.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: Layout.symbolColumn)
            Text(status.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.sm)
            if status.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            trailing()
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .opacity(status.isMissing ? 0.5 : 1)
    }
}
