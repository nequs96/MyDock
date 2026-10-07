import AppKit
import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var history: ProfileLibrary
    @State private var selected: ProfileLibraryEntry?
    @State private var message: String?
    @State private var confirmingClear = false

    var body: some View {
        GroupedSection("Recovery & history", footer: "Restoring creates a new profile.") {
            GroupedRow("Include private text for this session", isOn: $history.includeNotes)
                .help("Includes Sticky Note text, Quick Checklist tasks, and Text Snippets in new history entries until MyDock quits. File Shelf references and Quick Links are always omitted. Turning this off does not remove text from existing history entries.")
            if let error = history.errorMessage { GroupedRow(error).foregroundStyle(.orange) }
            if history.entries.isEmpty { GroupedRow("No previous layouts yet.") }
            ForEach(history.entries) { entry in
                GroupedRow(entry.profile.name, subtitle: "\(entry.reason) · \(entry.recordedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.profile.items.count) items") {
                    HStack {
                    Button("Inspect") { selected = entry }
                    Button("Restore as New") { restore(entry) }
                    }
                }
            }
            GroupedRow("Clear History…", role: .destructive) { confirmingClear = true }.disabled(history.entries.isEmpty)
            if let message { GroupedRow(message).textSelection(.enabled) }
        }
        .id("Recovery & history")
        .help("Previous profile layouts are kept locally for 14 days, up to 25 entries and 8 MB. Credentials, connected account references, cached usage, hydration history, and running sessions are removed.")
        .confirmationDialog("Clear local profile history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .sheet(item: $selected) { entry in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Spacer(); Button("Done") { selected = nil }.buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction) }
                    .overlay { Text(entry.profile.name).font(DockDesign.sectionTitle).allowsHitTesting(false) }
                if entry.profile.kind == .custom { DockLayoutPreview(store: store, profile: entry.profile) }
                DockScrollView { VStack(alignment: .leading) { ForEach(entry.profile.items) { Text($0.displayName) } } }.frame(maxHeight: 250)
                HStack { Spacer(); Button("Restore as New") { restore(entry); selected = nil } }
            }.padding(24).frame(width: 600).background(DockDesign.page).buttonStyle(DockButtonStyle())
        }
    }
    private func restore(_ entry: ProfileLibraryEntry) {
        do {
            // Like backup Restore, a restored layout is added beside the current Dock, not switched to.
            let id = try store.createProfile(ProfileSanitizer.newIdentity(entry.profile), activate: false)
            message = "Restored \(store.state.profiles.first(where: { $0.id == id })?.name ?? "profile")."
        } catch { message = error.localizedDescription }
    }
}
