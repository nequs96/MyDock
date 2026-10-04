import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var generalPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        AppLifecycleSettingsView()
        RecoveryCenterView(store: store, history: store.history)
        DockSettingSection(title: "Saved Docks") {
            Toggle("Include personal widget data", isOn: $includePersonalBackupData)
            Text(includePersonalBackupData
                 ? "Includes notes, checklists, snippets, shelf files, histories, timers, alarms and saved selections. Keep this file private. Credentials, permissions and cached provider readings are always excluded."
                 : "Layout only: notes, checklists, snippets, histories, timers, alarms, local calendar selections and connection assignments are removed. App, file, folder, and link locations remain in the layout. Cached provider readings are never included.")
                .font(DockDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Back Up…") { exportBackup() }
                Button("Restore…") { importBackup() }
            }
            if let backupMessage { Text(backupMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Text("macOS Dock profiles")
                Spacer()
                Text("\(store.nativeProfiles.count)").foregroundStyle(.secondary)
            }
            HStack {
                Text("Custom Dock profiles")
                Spacer()
                Text("\(store.customProfiles.count)").foregroundStyle(.secondary)
            }
        }
        PrivacyHelpSection()
        DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
        DockSettingSection(title: "Diagnostics") {
            Text("Export a redacted status report for troubleshooting. It contains app and macOS versions, item counts, appearance choices, save status, and recent event codes. It excludes profile names, app and file paths, URLs, note text, calendar content, credentials, and window images.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Export Diagnostics…") { exportDiagnostics() }
            if let diagnosticsMessage {
                Text(diagnosticsMessage).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        }
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyDock-Backup.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profiles = includePersonalBackupData ? store.state.profiles : store.state.profiles.map { ProfileSanitizer.sanitize($0) }
            let data = try BackupManager.makeArchive(from: profiles)
            try data.write(to: url, options: .atomic)
            backupMessage = "Saved \(store.state.profiles.count) profile(s)."
            DiagnosticsService.shared.record(.backupExported)
        } catch {
            backupMessage = error.localizedDescription
            DiagnosticsService.shared.record(.backupOperationFailed)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = try BackupManager.readArchive(from: url)
            try store.importProfiles(report.importedProfiles)
            var message = "Restored \(report.importedProfiles.count) profile(s)."
            if !report.missingItems.isEmpty {
                message += " Missing apps or paths: " + report.missingItems.joined(separator: "; ")
            }
            backupMessage = message
            DiagnosticsService.shared.record(.backupImported)
        } catch {
            backupMessage = error.localizedDescription
            DiagnosticsService.shared.record(.backupOperationFailed)
        }
    }

    private func exportDiagnostics() {
        do {
            diagnosticsPreview = DiagnosticsPreviewPayload(data: try DiagnosticsService.shared.reportData(for: store))
            diagnosticsMessage = nil
        } catch {
            diagnosticsMessage = "Could not prepare diagnostics: \(error.localizedDescription)"
        }
    }
}
