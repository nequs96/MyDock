import AppKit
import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var history: ProfileLibrary
    @State private var selected: ProfileLibraryEntry?
    @State private var message: String?
    @State private var confirmingClear = false

    var body: some View {
        DockSettingSection(title: "Recovery & history") {
            Text("Previous profile layouts are kept locally for 14 days, up to 25 entries and 8 MB. Credentials, connected account references, cached usage, hydration history, and running sessions are removed. Restoring creates a new profile.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Include Sticky Note text in future history", isOn: $history.includeNotes)
            if let error = history.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            if history.entries.isEmpty { Text("No previous layouts yet.").foregroundStyle(.secondary) }
            ForEach(history.entries.prefix(10)) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.profile.name).font(.callout.weight(.semibold))
                        Text("\(entry.reason) · \(entry.recordedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.profile.items.count) items")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Inspect") { selected = entry }
                    Button("Restore as New") { restore(entry) }
                }
            }
            Button("Clear History…", role: .destructive) { confirmingClear = true }.disabled(history.entries.isEmpty)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
        .confirmationDialog("Clear local profile history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .sheet(item: $selected) { entry in
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.profile.name).font(.title2)
                if entry.profile.kind == .custom { DockLayoutPreview(store: store, profile: entry.profile) }
                DockScrollView { VStack(alignment: .leading) { ForEach(entry.profile.items) { Text($0.displayName) } } }.frame(maxHeight: 250)
                HStack { Button("Close") { selected = nil }; Spacer(); Button("Restore as New") { restore(entry); selected = nil } }
            }.padding(24).frame(width: 600).background(DockDesign.page).buttonStyle(DockButtonStyle())
        }
    }
    private func restore(_ entry: ProfileLibraryEntry) {
        do {
            let id = try store.createProfile(ProfileSanitizer.newIdentity(entry.profile))
            message = "Restored \(store.state.profiles.first(where: { $0.id == id })?.name ?? "profile")."
        } catch { message = error.localizedDescription }
    }
}
