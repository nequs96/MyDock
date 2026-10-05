import AppKit
import SwiftUI

/// The Dock inspector's Workspace section: choose which items open together, then start them.
struct DockWorkspaceSection: View {
    let profile: DockProfile
    let setIncluded: (UUID, Bool) -> Void
    let start: () -> Void

    var body: some View {
        let candidates = profile.workspaceCandidates
        GroupedSection("Workspace", footer: candidates.isEmpty
                       ? "Add apps, folders, files or links to open them together."
                       : "Chosen items open together. Running apps are brought forward.") {
            ForEach(candidates) { item in
                GroupedRow(item.displayName, symbol: DockWorkspaceSection.symbol(for: item),
                           isOn: Binding(get: { profile.isInWorkspace(item.id) },
                                         set: { setIncluded(item.id, $0) }))
            }
            GroupedRow("Start Workspace…", role: .button, action: start)
                .disabled(!profile.hasWorkspace)
                .help(profile.hasWorkspace ? "Preview and open the chosen items" : "Choose at least one item first")
        }
    }

    static func symbol(for item: DockItem) -> String {
        switch item.type {
        case .application: "app"
        case .folder: "folder"
        case .file: "doc"
        case .link: "link"
        default: "square"
        }
    }
}

/// Identifies one Start Workspace request; a fresh request always starts at the preview.
struct WorkspaceStartRequest: Identifiable {
    let id = UUID()
    let profile: DockProfile
    let isCurrentDock: Bool
    let canLocate: Bool
}

/// Lets ⌘K start a Dock's workspace in the window that hosts the command palette.
struct WorkspaceStartHandler {
    let start: (UUID) -> Void
}

private struct WorkspaceStartHandlerKey: EnvironmentKey {
    static var defaultValue: WorkspaceStartHandler? { nil }
}

extension EnvironmentValues {
    var workspaceStartHandler: WorkspaceStartHandler? {
        get { self[WorkspaceStartHandlerKey.self] }
        set { self[WorkspaceStartHandlerKey.self] = newValue }
    }
}

/// Preview, then per-target outcomes. Starting never quits or closes anything.
struct WorkspaceStartSheet: View {
    let request: WorkspaceStartRequest
    let switchToDock: () -> Void
    let locate: (DockItem) -> DockItem?
    let close: () -> Void
    @StateObject private var run: WorkspaceStartRun
    /// Off by default: switching (for a macOS Dock profile, applying it to Apple's Dock) is an explicit opt-in.
    @State private var alsoSwitch = false

    init(request: WorkspaceStartRequest, launcher: any WorkspaceLaunching,
         switchToDock: @escaping () -> Void, locate: @escaping (DockItem) -> DockItem?, close: @escaping () -> Void) {
        self.request = request
        self.switchToDock = switchToDock
        self.locate = locate
        self.close = close
        _run = StateObject(wrappedValue: WorkspaceStartRun(targets: request.profile.workspaceTargets, launcher: launcher))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Workspace").font(DockDesign.sectionTitle).accessibilityAddTraits(.isHeader)
                Text(request.profile.name).font(DockDesign.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ScrollView {
                GroupedSection {
                    ForEach(run.results) { result in
                        GroupedRow(result.item.displayName, subtitle: failureReason(result.outcome),
                                   symbol: DockWorkspaceSection.symbol(for: result.item),
                                   accessory: { status(for: result) })
                    }
                }
            }.frame(maxHeight: 340)
            if run.phase == .preview && !request.isCurrentDock {
                Toggle("Also switch to this Dock", isOn: $alsoSwitch).toggleStyle(.checkbox)
            }
            HStack {
                if run.phase == .cancelled {
                    Text("Stopped. Nothing was closed.").font(DockDesign.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch run.phase {
                case .preview:
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    PillButton("Start", systemImage: "play.fill", action: begin).keyboardShortcut(.defaultAction)
                        .disabled(run.results.allSatisfy { $0.planned == .missing })
                case .running:
                    ProgressView().controlSize(.small).accessibilityLabel("Opening")
                    Button("Cancel") { run.cancel() }.keyboardShortcut(.cancelAction)
                        .help("Stop opening the remaining items")
                case .finished, .cancelled:
                    PillButton("Done", action: close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(DockDesign.body)
        .padding(24).frame(width: 440).background(DockDesign.page)
    }

    private func begin() {
        if alsoSwitch && !request.isCurrentDock { switchToDock() }
        let run = run
        Task { await run.start() }
    }

    private func failureReason(_ outcome: WorkspaceTargetOutcome) -> String? {
        if case .failed(let reason) = outcome { return reason }
        return nil
    }

    @ViewBuilder private func status(for result: WorkspaceTargetResult) -> some View {
        switch result.outcome {
        case .pending:
            Text(previewLabel(result.planned)).foregroundStyle(result.planned == .missing ? Color.orange : Color.secondary)
        case .opening:
            ProgressView().controlSize(.small).accessibilityLabel("Opening")
        case .opened:
            Label("Opened", systemImage: "checkmark").foregroundStyle(.secondary)
        case .alreadyRunning:
            Label("Already running", systemImage: "checkmark").foregroundStyle(.secondary)
        case .missing:
            HStack(spacing: 8) {
                Text("Missing").foregroundStyle(.orange)
                if request.canLocate && run.isComplete {
                    Button("Locate…") {
                        guard let repaired = locate(result.item) else { return }
                        let run = run
                        Task { await run.retry(repaired) }
                    }
                }
            }
        case .failed:
            Text("Failed").foregroundStyle(.orange)
        case .cancelled:
            Text("Not opened").foregroundStyle(.secondary)
        }
    }

    private func previewLabel(_ action: WorkspaceStartAction) -> String {
        switch action {
        case .open: "Opens"
        case .activate: "Running · brought forward"
        case .missing: "Missing"
        }
    }
}
