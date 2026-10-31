import SwiftUI

/// Names an item and picks where it shows. Opens when an entity is first
/// shown anywhere (a toggle in Settings > Entities), and from Rename…
/// A blank name uses the name from Home Assistant.
struct ItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: ItemDraft
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text(draft.homeAssistantName))
                        .focused($nameFocused)
                        .onSubmit(save)
                } header: {
                    Text(draft.entityID)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } footer: {
                    Text("Leave blank to use the name from Home Assistant.")
                        .foregroundStyle(.secondary)
                }
                Section("Show In") {
                    Toggle(isOn: $draft.showInMenuBar) {
                        Label(Place.menuBar.title, systemImage: Place.menuBar.symbol)
                    }
                    Toggle(isOn: $draft.showInWindow) {
                        Label(Place.window.title, systemImage: Place.window.symbol)
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Show" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isNew && !draft.showInMenuBar && !draft.showInWindow)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.margin)
        }
        .frame(width: Layout.sheetWidth)
        // The sheet's one job is typing a name, so its field has focus.
        .onAppear { nameFocused = true }
    }

    private func save() {
        model.save(draft)
        dismiss()
    }
}
