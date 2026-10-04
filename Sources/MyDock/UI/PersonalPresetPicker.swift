import AppKit
import SwiftUI

struct PersonalPresetPicker: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var library: ProfileLibrary
    var select: (DockProfile) -> Void
    @State private var message: String?

    var body: some View {
        GroupedSection("Personal presets", footer: message ?? library.errorMessage) {
            GroupedRow("Import…", role: .button) { importPreset() }
            if library.entries.isEmpty {
                GroupedRow("Save or import a Dock preset to keep it here.")
            }
            ForEach(library.entries) { entry in
                GroupedRow(entry.profile.name) {
                    HStack {
                        Button("Use") { select(ProfileSanitizer.newIdentity(entry.profile)) }
                            .accessibilityLabel("Use preset \(entry.profile.name)")
                        Button("Export…") { exportPreset(entry.id) }
                            .accessibilityLabel("Export preset \(entry.profile.name)")
                        Button("Remove", role: .destructive) { library.remove(entry.id) }
                            .accessibilityLabel("Remove preset \(entry.profile.name)")
                    }
                }
            }
        }
    }
    private func importPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BackupManager.boundedArchiveData(from: url, maximumBytes: 8 * 1_024 * 1_024)
            try library.importPreset(data)
            message = library.errorMessage ?? "Preset imported. Preview it before creating a Dock."
        } catch { message = error.localizedDescription }
    }
    private func exportPreset(_ id: UUID) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MyDock-preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.exportPreset(id).write(to: url, options: .atomic); message = "Sanitized preset exported." }
        catch { message = error.localizedDescription }
    }
}
