import AppKit
import SwiftUI

struct PersonalPresetPicker: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var library: ProfileLibrary
    var select: (DockProfile) -> Void
    @State private var message: String?
    @State private var pendingRemoval: ProfileLibraryEntry?

    var body: some View {
        GroupedSection("Personal presets") {
            // A library error always shows, even after an earlier success message.
            if let error = library.errorMessage {
                GroupedRow("Preset library", subtitle: error, symbol: "exclamationmark.triangle.fill", color: DockDesign.Status.warning)
                    .help(error).textSelection(.enabled)
            }
            if let message { GroupedRow(message).help(message).textSelection(.enabled) }
            GroupedRow("Import…", role: .button) { importPreset() }
            if library.entries.isEmpty {
                GalleryEmptyState(title: "No Personal Presets", detail: "Save or import a Dock preset to keep it here.",
                                  symbol: "square.grid.2x2", compact: true)
            }
            ForEach(library.entries) { entry in
                GroupedRow(entry.profile.name) {
                    HStack {
                        Button("Use") { select(ProfileSanitizer.newIdentity(entry.profile)) }
                            .accessibilityLabel("Use preset \(entry.profile.name)")
                        Button("Export…") { exportPreset(entry.id) }
                            .accessibilityLabel("Export preset \(entry.profile.name)")
                        Button("Remove…", role: .destructive) { pendingRemoval = entry }
                            .accessibilityLabel("Remove preset \(entry.profile.name)")
                    }
                    .buttonStyle(DockButtonStyle())
                }
            }
        }
        .confirmationDialog("Remove \(pendingRemoval?.profile.name ?? "this preset")?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Preset", role: .destructive) {
                guard let entry = pendingRemoval else { return }
                pendingRemoval = nil
                message = nil
                library.remove(entry.id)
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("Docks made from it are kept.") }
    }
    private func importPreset() {
        message = nil
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BackupManager.boundedArchiveData(from: url, maximumBytes: 8 * 1_024 * 1_024)
            try library.importPreset(data)
            message = "Preset imported. Preview it before creating a Dock."
        } catch {
            // A library error already has its own row.
            if error.localizedDescription != library.errorMessage { message = error.localizedDescription }
        }
    }
    private func exportPreset(_ id: UUID) {
        message = nil
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MyDock-preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.exportPreset(id).write(to: url, options: .atomic); message = "Preset exported without personal data." }
        catch { message = error.localizedDescription }
    }
}
