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
        GroupedSection("Saved Docks", footer: includePersonalBackupData
            ? "Personal backups include private widget data."
            : "Layout backups exclude personal widget data.") {
            GroupedRow("Include personal widget data", isOn: $includePersonalBackupData)
                .help("Personal backups include notes, lists, snippets, shelf files, history, timers, alarms and selections. Layout backups keep app, file, folder and link locations. Credentials, permissions and provider caches are always excluded; layout backups also exclude connections and personal data.")
            GroupedRow("Back Up…", role: .button) { exportBackup() }
            GroupedRow("Restore…", role: .button) { importBackup() }
            GroupedRow("Export Dock…", role: .button) {
                // A shared Dock never inherits the backup toggle (on by default): personal data is opt-in in the sheet.
                dockExportRequest = PortableDockExportRequest(profiles: store.state.profiles, selectedID: store.activeCustomProfile?.id,
                                                              includePersonalData: false)
            }
            .disabled(store.state.profiles.isEmpty)
            .help("Review and export one Dock to use on another Mac or share")
            GroupedRow("Import Dock…", role: .button) { importDock() }
                .help("Preview a Dock file and add it as a new Dock")
            if let backupMessage { Text(backupMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            GroupedRow("macOS Dock profiles", value: "\(store.nativeProfiles.count)")
            GroupedRow("Custom Dock profiles", value: "\(store.customProfiles.count)")
        }.id("Saved Docks")
        PrivacyHelpSection()
        GroupedSection("Advanced", footer: "Review a redacted report before exporting.") {
            SettingsExpansionRow(title: "Diagnostics", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    GroupedRow("Export Diagnostics…", role: .button) { exportDiagnostics() }
                        .help("Includes versions, counts, appearance, save status and event codes. Names, paths, URLs, personal content, credentials and images are excluded.")
                    if let diagnosticsMessage {
                        Text(diagnosticsMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        }.id("Diagnostics")
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

    private func importDock() {
        do {
            if let preview = try PortableDockPanels.chooseImport(existingNames: store.state.profiles.map(\.name)) {
                dockImportPreview = preview
            }
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    func addImportedDock(_ preview: PortableDockImportPreview) {
        dockImportPreview = nil
        do {
            try PortableDockPackage.importAsNew(preview, into: store)
            backupMessage = "Added \(preview.profile.name) as a new Dock."
        } catch {
            backupMessage = error.localizedDescription
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
