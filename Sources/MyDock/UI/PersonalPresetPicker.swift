import AppKit
import SwiftUI

struct PersonalPresetPicker: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var library: ProfileLibrary
    var select: (DockProfile) -> Void
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal presets").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Import…") { importPreset() }
            }
            if library.entries.isEmpty {
                Text("Save a Dock as a preset or import one to keep it here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(library.entries) { entry in
                HStack {
                    Button(entry.profile.name) { select(ProfileSanitizer.newIdentity(entry.profile)) }
                    Spacer()
                    Button("Export…") { exportPreset(entry.id) }
                    Button("Remove", role: .destructive) { library.remove(entry.id) }
                }.font(.caption)
            }
            if let message = message ?? library.errorMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
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
