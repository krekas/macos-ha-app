import SwiftData
import SwiftUI

/// The main window: the groups and items, like the menu, in a resizable window.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \MenuGroup.order) private var groups: [MenuGroup]

    var body: some View {
        content
            .frame(minWidth: Layout.mainMinWidth, minHeight: Layout.mainMinHeight)
            .navigationSubtitle(model.connection.isConnected ? "Connected" : "Not connected")
            .noInitialFocus()
    }

    @ViewBuilder
    private var content: some View {
        let filled = groups.filter { !$0.items.isEmpty }
        if filled.isEmpty {
            if model.connection.isConnected {
                ContentUnavailableView {
                    Label("No Items Yet", systemImage: "house")
                } description: {
                    Text("Add lights, switches, and sensors from Home Assistant.")
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
                        ForEach(group.sortedItems) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}
