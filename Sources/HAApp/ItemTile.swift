import SwiftUI

/// One item in the main window, as a Home Assistant style tile: the symbol in
/// a round badge, the name, and the live value under it. An on/off entity
/// fills with the accent while it's on; a click anywhere turns it on or off.
struct ItemTile: View {
    @Environment(AppModel.self) private var model
    let item: MenuItem
    @State private var isHovered = false

    var body: some View {
        let status = ItemStatus(item: item, model: model)
        let tile = HStack(spacing: Space.md) {
            badge(status)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(status.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status.value)
                    .font(.subheadline)
                    .foregroundStyle(status.isOn ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Motion.numberRoll, value: status.value)
            }
            Spacer(minLength: 0)
            if status.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Surfaces.warning)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, minHeight: Layout.tileHeight, alignment: .leading)
        .background(background(status), in: Radius.shape(Radius.md))
        .overlay(Radius.shape(Radius.md).strokeBorder(Surfaces.hairline.opacity(status.isOn ? 0 : 0.5)))
        .contentShape(Radius.shape(Radius.md))
        .opacity(status.isMissing || status.isUnavailable ? 0.5 : 1)
        .animation(Motion.quick, value: status.isOn)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .help(status.help)

        if status.isToggleable {
            tile
                .onTapGesture { status.toggle() }
                .itemToggleAccessibility(status)
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }

    private func badge(_ status: ItemStatus) -> some View {
        Image(systemName: status.symbol)
            .symbolVariant(status.isOn ? .fill : .none)
            .font(.title3)
            .foregroundStyle(status.isOn ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(.secondary))
            .frame(width: Layout.tileBadge, height: Layout.tileBadge)
            .background(status.isOn ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.fill.tertiary), in: Circle())
    }

    private func background(_ status: ItemStatus) -> AnyShapeStyle {
        if status.isOn { return AnyShapeStyle(Surfaces.accentWash) }
        let lifts = isHovered && status.canToggle
        return lifts ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary)
    }
}
