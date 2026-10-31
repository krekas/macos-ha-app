import SwiftData
import SwiftUI
import HAAppKit

/// Settings > Entities: every entity from the last scan, grouped by device,
/// area, or type, with a search field in the toolbar and a Rescan button.
/// Each entity's toggles show it in the menu bar, the window, or both.
struct EntitiesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @Query private var items: [MenuItem]
    /// The naming sheet, open while set.
    @State private var draft: ItemDraft?

    var body: some View {
        let store = model.entities
        Group {
            if let catalog = store.catalog {
                list(catalog)
            } else {
                empty
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search entities")
        .sheet(item: $draft) { ItemSheet(draft: $0) }
    }

    private func list(_ catalog: EntityCatalog) -> some View {
        @Bindable var store = model.entities
        let sections = catalog.sections(by: store.grouping, matching: query)
        let itemByID = Dictionary(items.map { ($0.entityID, $0) }, uniquingKeysWith: { first, _ in first })
        return Form {
            Section {
                LabeledContent {
                    rescanButton
                } label: {
                    Text("\(catalog.entities.count) entities on \(catalog.deviceCount) devices")
                    scanStatus(catalog)
                }
                Picker("Group by", selection: $store.grouping) {
                    ForEach(EntityGrouping.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Sections") {
                    HStack(spacing: Space.sm) {
                        Button("Expand All") { store.expandAll() }
                            .disabled(searching)
                        Button("Collapse All") { store.collapseAll() }
                            .disabled(searching)
                    }
                }
            } footer: {
                Text("Turn on Menu Bar or Window to show an entity there. Right-click an entity to rename it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sections.isEmpty {
                Section {
                    Text("No entities match “\(query)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            ForEach(sections) { section in
                Section(isExpanded: expanded(section)) {
                    ForEach(section.entities) { entity in
                        EntityRow(entity: entity, grouping: store.grouping, item: itemByID[entity.entityID]) { place, shown in
                            show(entity, in: place, shown, item: itemByID[entity.entityID])
                        } rename: {
                            draft = model.draft(for: entity.entityID)
                        }
                    }
                } header: {
                    HStack {
                        Text(section.title)
                        Spacer()
                        Text("\(section.entities.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: sections.map(\.id), initial: true) { _, ids in store.visibleSections = ids }
    }

    /// The first place an entity shows asks for a name. After that the
    /// toggles just show and hide it.
    private func show(_ entity: KnownEntity, in place: Place, _ shown: Bool, item: MenuItem?) {
        if shown && !(item?.isShownAnywhere ?? false) {
            draft = model.draft(for: entity.entityID, turningOn: place)
        } else {
            model.setShown(entity.entityID, in: place, shown)
        }
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Sections start collapsed, so a big home opens fast. A search opens
    /// every section with a match; clearing it brings back the user's choice.
    private func expanded(_ section: EntitySection) -> Binding<Bool> {
        Binding {
            searching || model.entities.isExpanded(section.id)
        } set: { open in
            model.entities.setExpanded(section.id, open)
        }
    }

    @ViewBuilder
    private func scanStatus(_ catalog: EntityCatalog) -> some View {
        if model.entities.isScanning {
            Text("Scanning…")
        } else if let error = model.entities.scanError {
            Text(error).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Scanned \(catalog.scannedAt, format: .relative(presentation: .named))")
        }
    }

    private var rescanButton: some View {
        HStack(spacing: Space.sm) {
            if model.entities.isScanning {
                ProgressView().controlSize(.small)
            }
            Button("Rescan", systemImage: "arrow.clockwise") {
                Task { await model.rescanEntities() }
            }
            .disabled(!model.canRescan)
            .help(model.connection.isConnected
                  ? "Read the entity list from Home Assistant again (⇧⌘R)"
                  : "Connect to Home Assistant in General to rescan")
        }
    }

    @ViewBuilder
    private var empty: some View {
        if model.entities.isScanning {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Scanning your Home Assistant entities…")
            }
        } else if model.connection.isConnected {
            ContentUnavailableView {
                Label("No Entities Yet", systemImage: "list.bullet")
            } description: {
                Text(model.entities.scanError ?? "Scan Home Assistant to list your devices, sensors, and other entities.")
            } actions: {
                Button("Scan Entities") { Task { await model.rescanEntities() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No Entities Yet", systemImage: "list.bullet")
            } description: {
                Text("Connect to Home Assistant to scan your entities.")
            } actions: {
                Button("Connection Settings") { model.settingsTab = .general }
            }
        }
    }
}

/// One entity: symbol, name, and entity id, with a toggle for each place it can show.
private struct EntityRow: View {
    let entity: KnownEntity
    let grouping: EntityGrouping
    let item: MenuItem?
    let setShown: (Place, Bool) -> Void
    let rename: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: Space.xs) {
                ForEach(Place.allCases) { place in
                    let shown = item?.isShown(in: place) ?? false
                    // A checkmark too, so "on" doesn't rely on color alone.
                    Toggle(isOn: Binding { shown } set: { setShown(place, $0) }) {
                        if shown { Label(place.title, systemImage: "checkmark") } else { Text(place.title) }
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(help(place, shown: shown))
                    .accessibilityLabel("Show in \(place.title)")
                }
            }
        } label: {
            Label {
                Text(title).lineLimit(1)
                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: entity.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.symbolColumn)
            }
        }
        .help(entity.entityID)
        .contextMenu {
            Button("Rename…", action: rename)
            Button("Copy Entity ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entity.entityID, forType: .string)
            }
        }
    }

    /// The user's name for it, or Home Assistant's. Under a device header,
    /// the device name is already shown.
    private var title: String {
        if let given = item?.givenName { return given }
        return grouping == .device ? entity.nameWithinDevice : entity.name
    }

    /// The entity id, after Home Assistant's name when the user renamed it,
    /// and after the device under an area or type header.
    private var subtitle: String {
        var parts: [String] = []
        if item?.givenName != nil { parts.append(entity.name) }
        if grouping != .device, let device = entity.deviceName { parts.append(device) }
        parts.append(entity.entityID)
        return parts.joined(separator: " · ")
    }

    private func help(_ place: Place, shown: Bool) -> String {
        let where_ = place == .menuBar ? "the menu bar" : "the window"
        return shown ? "Shown in \(where_). Click to hide." : "Show in \(where_)"
    }
}
