import SwiftUI

/// The Settings window (Command-Comma). Topics sit in a sidebar on the left,
/// grouped in sections, like System Settings; the selected topic's grouped
/// Form fills the right side. The window title follows the topic. The owner
/// asked for a sidebar instead of toolbar tabs, so the app can grow past six
/// topics without changing the window.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.settingsTab) {
                ForEach(SettingsSection.allCases) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            Label(tab.title, systemImage: tab.symbol)
                                .tag(tab)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(Layout.settingsSidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            page(model.settingsTab)
                .navigationTitle(model.settingsTab.title)
        }
        .frame(width: Layout.settingsSidebarWidth + Layout.settingsWidth,
               height: Layout.settingsHeight)
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
    }
}

/// The sidebar's sections, in order. Each holds one or more tabs.
enum SettingsSection: String, CaseIterable, Identifiable {
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "HAApp"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

/// The Settings topics. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    // Menu (S-006) comes with its story.
    case general
    case appearance

    var id: String { rawValue }

    var section: SettingsSection {
        switch self {
        case .general, .appearance: .app
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}
