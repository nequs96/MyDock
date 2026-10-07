import AppKit
import Foundation

/// What Start Workspace will do with one target. Starting never quits or closes anything.
enum WorkspaceStartAction: Equatable, Sendable {
    case open
    /// A running application is brought forward instead of being launched again.
    case activate
    case missing
}

enum WorkspaceStartPlan {
    /// Only running applications are deduplicated; folders, files and links always open.
    static func action(for item: DockItem, isMissing: Bool, isRunning: Bool) -> WorkspaceStartAction {
        if isMissing { return .missing }
        if item.type == .application && isRunning { return .activate }
        return .open
    }
}

enum WorkspaceTargetOutcome: Equatable, Sendable {
    case pending
    case opening
    case opened
    case alreadyRunning
    case missing
    case failed(String)
    /// Not attempted because the user cancelled the remaining targets.
    case cancelled

    var isFinal: Bool {
        switch self {
        case .pending, .opening: false
        default: true
        }
    }
}

struct WorkspaceTargetResult: Identifiable, Equatable {
    var item: DockItem
    var planned: WorkspaceStartAction
    var outcome: WorkspaceTargetOutcome = .pending
    var id: UUID { item.id }
}

/// Native effects behind one seam so tests never launch or open anything.
@MainActor
protocol WorkspaceLaunching {
    func isMissing(_ item: DockItem) -> Bool
    func isRunning(_ item: DockItem) -> Bool
    /// Brings the single running instance forward. False when it is no longer running.
    func activate(_ item: DockItem) -> Bool
    /// Opens the target. Returns nil on success or a short failure reason.
    func open(_ item: DockItem) async -> String?
}

/// Opens targets one at a time, in Dock order, and records an outcome for each.
@MainActor
final class WorkspaceStartRun: ObservableObject {
    enum Phase: Equatable { case preview, running, finished, cancelled }

    @Published private(set) var results: [WorkspaceTargetResult]
    @Published private(set) var phase: Phase = .preview
    private let launcher: any WorkspaceLaunching
    private var cancelRequested = false

    init(targets: [DockItem], launcher: any WorkspaceLaunching) {
        self.launcher = launcher
        results = targets.map { item in
            WorkspaceTargetResult(item: item, planned: WorkspaceStartPlan.action(
                for: item, isMissing: launcher.isMissing(item), isRunning: launcher.isRunning(item)))
        }
    }

    var isRunning: Bool { phase == .running }
    var isComplete: Bool { phase == .finished || phase == .cancelled }

    func start() async {
        guard phase == .preview else { return }
        phase = .running
        for index in results.indices {
            if cancelRequested { break }
            results[index].outcome = .opening
            results[index].outcome = await perform(results[index].item)
        }
        if cancelRequested {
            for index in results.indices where !results[index].outcome.isFinal { results[index].outcome = .cancelled }
            phase = .cancelled
        } else {
            phase = .finished
        }
    }

    /// Stops the targets that have not started. A target already opening completes.
    func cancel() {
        guard phase == .running else { return }
        cancelRequested = true
    }

    /// After Locate… repairs a missing target, open the repaired copy once.
    func retry(_ repaired: DockItem) async {
        guard isComplete, let index = results.firstIndex(where: { $0.id == repaired.id }),
              results[index].outcome == .missing else { return }
        results[index].item = repaired
        results[index].outcome = .opening
        results[index].outcome = await perform(repaired)
    }

    private func perform(_ item: DockItem) async -> WorkspaceTargetOutcome {
        // Decide at the moment of opening: an app may have launched or quit since the preview.
        switch WorkspaceStartPlan.action(for: item, isMissing: launcher.isMissing(item), isRunning: launcher.isRunning(item)) {
        case .missing:
            return .missing
        case .activate:
            if launcher.activate(item) { return .alreadyRunning }
            fallthrough
        case .open:
            if let failure = await launcher.open(item) { return .failed(failure) }
            return .opened
        }
    }
}

/// The production launcher. Every native effect is behind the validation boundary.
@MainActor
struct SystemWorkspaceLauncher: WorkspaceLaunching {
    func isMissing(_ item: DockItem) -> Bool {
        if item.type == .link {
            guard let url = item.url else { return true }
            return DockLinkPolicy.validatedURL(url.absoluteString) == nil
        }
        return AppLauncher.isMissingTarget(item)
    }

    func isRunning(_ item: DockItem) -> Bool {
        AppLauncher.runningApplication(for: item) != nil
    }

    func activate(_ item: DockItem) -> Bool {
        guard AppRuntimeEnvironment.allowsNativeEffects, let app = AppLauncher.runningApplication(for: item) else { return false }
        return AppActivation.activate(app)
    }

    func open(_ item: DockItem) async -> String? {
        guard AppRuntimeEnvironment.allowsNativeEffects else {
            return ValidationBoundaryError.nativeEffectsDisabled.localizedDescription
        }
        guard let url = AppLauncher.resolvedURL(for: item) else { return "No saved location." }
        if item.type == .application {
            return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { @Sendable (_, error) in
                    continuation.resume(returning: error?.localizedDescription)
                }
            }
        }
        return NSWorkspace.shared.open(url) ? nil : "macOS could not open it."
    }
}
