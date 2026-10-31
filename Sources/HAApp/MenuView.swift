import SwiftData
import SwiftUI

/// What opens when you click the HAApp icon in the menu bar.
/// Live states, turning things on and off, and sensor values come with S-002 to S-005.
struct MenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \MenuGroup.order) private var groups: [MenuGroup]

    var body: some View {
        VStack(spacing: 0) {
            if groups.allSatisfy(\.items.isEmpty) {
                ContentUnavailableView {
                    Label("No Items Yet", systemImage: "house")
                } description: {
                    Text("Add lights, switches, and sensors from Home Assistant.")
                }
                .frame(maxWidth: .infinity, minHeight: Layout.menuEmptyHeight)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(groups.filter { !$0.items.isEmpty }) { group in
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
            ForEach(group.sortedItems) { item in
                ItemRow(item: item)
            }
        }
    }
}

struct ItemRow: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: item.symbol)
                .frame(width: Layout.symbolColumn)
                .foregroundStyle(.secondary)
            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .help(item.entityID)
        .accessibilityElement(children: .combine)
    }
}
