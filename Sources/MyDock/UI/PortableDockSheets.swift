import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Open and save panels for single-Dock packages. Packages use the existing JSON backup file type.
@MainActor
enum PortableDockPanels {
    /// Nil when the user cancels the panel.
    static func chooseImport(existingNames: [String]) throws -> PortableDockImportPreview? {
        let panel = NSOpenPanel()
        panel.title = "Import Dock"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try PortableDockPackage.readPackage(from: url, existingNames: existingNames)
    }

    /// Returns false when the user cancels the panel.
    static func save(_ profile: DockProfile, includePersonalData: Bool) throws -> Bool {
        let data = try PortableDockPackage.makePackage(from: profile, includePersonalData: includePersonalData)
        let panel = NSSavePanel()
        panel.title = "Export Dock"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = profile.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

/// Reviews what a Dock export contains before writing it.
struct PortableDockExportSheet: View {
    let profiles: [DockProfile]
    let close: () -> Void
    let exported: (String) -> Void
    @State private var selectedID: UUID?
    @State private var includePersonalData: Bool
    @State private var errorMessage: String?

    init(profiles: [DockProfile], selectedID: UUID?, includePersonalData: Bool,
         close: @escaping () -> Void, exported: @escaping (String) -> Void) {
        self.profiles = profiles
        self.close = close
        self.exported = exported
        _selectedID = State(initialValue: selectedID ?? profiles.first?.id)
        _includePersonalData = State(initialValue: includePersonalData)
    }

    private var profile: DockProfile? { profiles.first { $0.id == selectedID } ?? profiles.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DockSheetHeader(title: "Export Dock")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if profiles.count > 1 {
                        GroupedSection {
                            GroupedRow("Dock") {
                                Picker("Dock", selection: $selectedID) {
                                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                                }.labelsHidden().fixedSize()
                            }
                        }
                    }
                    if let profile {
                        GroupedSection("Contents", footer: "Locations of apps, files and folders are included.") {
                            GroupedRow("Name", value: profile.name)
                            ForEach(DockContentSummary(profile: profile).rows) { row in
                                GroupedRow(row.title, value: "\(row.count)")
                            }
                            if profile.hasWorkspace {
                                GroupedRow("Workspace", value: "\(profile.workspaceTargets.count)")
                            }
                        }
                    }
                    GroupedSection(footer: includePersonalData
                                   ? "Includes notes, lists and other personal widget data. Credentials are never included."
                                   : "Layout only. Personal widget data and credentials are left out.") {
                        GroupedRow("Include personal widget data", isOn: $includePersonalData)
                    }
                }
            }.frame(maxHeight: 400)
            if let errorMessage {
                Text(errorMessage).font(DockDesign.caption).foregroundStyle(DockDesign.Status.warning).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                PillButton("Export…", action: export).keyboardShortcut(.defaultAction).disabled(profile == nil)
            }
        }
        .font(DockDesign.body)
        .padding(24).frame(width: 440).background(DockDesign.page)
    }

    private func export() {
        guard let profile else { return }
        // A retry starts clean: an earlier failure does not linger after a cancelled or successful save.
        errorMessage = nil
        do {
            if try PortableDockPanels.save(profile, includePersonalData: includePersonalData) {
                exported("Exported \(profile.name).")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shows exactly what an imported Dock adds. It is always added as a new Dock.
struct PortableDockImportSheet: View {
    let preview: PortableDockImportPreview
    let add: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DockSheetHeader(title: "Import Dock")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSection(footer: "Will be added as a new Dock. Existing Docks are not changed.") {
                        GroupedRow("Name", value: preview.profile.name)
                        ForEach(preview.summary.rows) { row in
                            GroupedRow(row.title, value: "\(row.count)")
                        }
                        if preview.includesPersonalData {
                            GroupedRow("Personal widget data", value: "Included")
                        }
                    }
                    if !preview.unresolved.isEmpty {
                        GroupedSection("Not on this Mac") {
                            ForEach(preview.unresolved) { target in
                                GroupedRow(target.title, subtitle: target.fallback, value: target.reason)
                            }
                        }
                    }
                    if !preview.reconnections.isEmpty {
                        GroupedSection("Needs reconnecting") {
                            ForEach(preview.reconnections) { widget in
                                GroupedRow(widget.title, subtitle: widget.fallback)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                PillButton("Add Dock", action: add).keyboardShortcut(.defaultAction)
            }
        }
        .font(DockDesign.body)
        .padding(24).frame(width: 440).background(DockDesign.page)
    }
}

/// One reviewed backup before its Docks are added. Nothing is replaced: every Dock is added as a new copy.
struct BackupRestorePreview: Identifiable {
    let id = UUID()
    let report: BackupImportReport
    /// The name each Dock is added under, by profile ID. A name already used on this Mac gets the next free number,
    /// exactly as adding does.
    let addedNames: [UUID: String]
    /// The sheet lists at most this many missing apps or paths and counts the rest.
    static let missingItemLimit = 50

    @MainActor init(report: BackupImportReport, existingNames: [String]) {
        self.report = report
        let names = ProfileStore.importedProfileNames(report.importedProfiles, existing: existingNames)
        addedNames = Dictionary(zip(report.importedProfiles.map(\.id), names), uniquingKeysWith: { first, _ in first })
    }

    /// "Adds as Work 2" when the backup's name is already used; nil when the Dock keeps its name.
    func renameNote(for profile: DockProfile) -> String? {
        guard let name = addedNames[profile.id], name != profile.name else { return nil }
        return "Adds as \(name)"
    }

    var addTitle: String { "Add " + Self.docksPhrase(report.importedProfiles.count) }

    static func docksPhrase(_ count: Int) -> String { count == 1 ? "1 Dock" : "\(count) Docks" }
}

struct BackupRestoreSheet: View {
    let preview: BackupRestorePreview
    let add: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Docks from Backup").font(DockDesign.sectionTitle).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSection(footer: "Each Dock is added as a new Dock. Existing Docks are not changed.") {
                        ForEach(preview.report.importedProfiles) { profile in
                            GroupedRow(profile.name, subtitle: profile.kind.title, value: preview.renameNote(for: profile))
                        }
                    }
                    let missing = preview.report.missingItems
                    if !missing.isEmpty {
                        GroupedSection("Not on this Mac") {
                            ForEach(Array(missing.prefix(BackupRestorePreview.missingItemLimit).enumerated()), id: \.offset) { _, item in
                                GroupedRow(item)
                            }
                            if missing.count > BackupRestorePreview.missingItemLimit {
                                GroupedRow("\(missing.count - BackupRestorePreview.missingItemLimit) more")
                            }
                        }
                    }
                }
            }.frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                PillButton(preview.addTitle, action: add).keyboardShortcut(.defaultAction)
                    .disabled(preview.report.importedProfiles.isEmpty)
            }
        }
        .font(DockDesign.body)
        .padding(24).frame(width: 440).background(DockDesign.page)
    }
}

/// Identifies one export review; `profiles` holds one Dock from the editor or every Dock from Settings.
struct PortableDockExportRequest: Identifiable {
    let id = UUID()
    let profiles: [DockProfile]
    let selectedID: UUID?
    let includePersonalData: Bool
}
