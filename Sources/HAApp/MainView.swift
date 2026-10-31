import SwiftData
import SwiftUI

/// The main window: the items shown in the window (Settings > Entities), by group.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \MenuGroup.order) private var groups: [MenuGroup]
    @State private var draft: ItemDraft?

    var body: some View {
        content
            .frame(minWidth: Layout.mainMinWidth, minHeight: Layout.mainMinHeight)
            .navigationSubtitle(model.connection.isConnected ? "Connected" : "Not connected")
            .noInitialFocus()
            .sheet(item: $draft) { ItemSheet(draft: $0) }
    }

    @ViewBuilder
    private var content: some View {
        let filled = groups.filter { $0.items.contains { $0.showInWindow } }
        if filled.isEmpty {
            if model.connection.isConnected {
                ContentUnavailableView {
                    Label("No Items Yet", systemImage: "house")
                } description: {
                    Text("Choose what to show in Settings > Entities.")
                } actions: {
                    SettingsLink { Text("Open Settings…") }
                        .simultaneousGesture(TapGesture().onEnded { model.settingsTab = .entities })
                }
            } else {
                ContentUnavailableView {
                    Label("Connect to Home Assistant", systemImage: "house")
                } description: {
                    Text("Add your server URL and an access token in Settings.")
                } actions: {
                    SettingsLink { Text("Open Settings…") }
                        .buttonStyle(.borderedProminent)
                        .simultaneousGesture(TapGesture().onEnded { model.settingsTab = .general })
                }
            }
        } else {
            List {
                ForEach(filled) { group in
                    Section(group.title) {
                        ForEach(group.sortedItems.filter(\.showInWindow)) { item in
                            ItemRow(item: item)
                                .contextMenu {
                                    Button("Rename…") { draft = model.draft(for: item.entityID) }
                                    Button("Hide from Window") { model.setShown(item.entityID, in: .window, false) }
                                }
                        }
                    }
                }
            }
        }
    }
}
