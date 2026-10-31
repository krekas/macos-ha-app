import SwiftUI
import HAAppKit

/// Settings > Entities: every entity from the last scan, grouped by device,
/// area, or type, with a search field in the toolbar and a Rescan button.
struct EntitiesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

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
    }

    private func list(_ catalog: EntityCatalog) -> some View {
        @Bindable var store = model.entities
        let sections = catalog.sections(by: store.grouping, matching: query)
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
                        EntityRow(entity: entity, grouping: store.grouping)
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

/// One entity: symbol and name, with the entity id on the trailing side.
private struct EntityRow: View {
    let entity: KnownEntity
    let grouping: EntityGrouping

    var body: some View {
        LabeledContent {
            Text(entity.entityID)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } label: {
            Label {
                Text(name).lineLimit(1)
                if let detail { Text(detail).lineLimit(1) }
            } icon: {
                Image(systemName: entity.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.symbolColumn)
            }
        }
        .help(entity.entityID)
        .contextMenu {
            Button("Copy Entity ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entity.entityID, forType: .string)
            }
        }
    }

    /// Under a device header, the device name is already shown.
    private var name: String {
        grouping == .device ? entity.nameWithinDevice : entity.name
    }

    /// The other grouping's context: the area under a device, the device under an area or type.
    private var detail: String? {
        switch grouping {
        case .device: nil
        case .area, .type: entity.deviceName
        }
    }
}
