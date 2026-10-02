import Combine
import Foundation

/// Watches only the pinned-app portion of Apple's Dock when the user opts in.
@MainActor
final class NativeDockAutoSaveMonitor: ObservableObject {
    static let shared = NativeDockAutoSaveMonitor(store: .shared, controller: .shared,
                                                   backend: UserDefaultsDockPreferencesBackend())

    @Published private(set) var errorMessage: String?

    private let store: ProfileStore
    private let controller: NativeDockController
    private let backend: DockPreferencesBackend
    private let pollingInterval: Duration?
    private let gate = DockSystemOperationGate.shared
    private var pollingTask: Task<Void, Never>?
    private var selectedProfileID: UUID?
    private var lastObservedSignatures: [String]?
    private var lastSeenAppliedGeneration: UInt64 = 0

    init(store: ProfileStore, controller: NativeDockController, backend: DockPreferencesBackend,
         pollingInterval: Duration? = .seconds(5)) {
        self.store = store
        self.controller = controller
        self.backend = backend
        self.pollingInterval = pollingInterval
    }

    func configure(enabled: Bool, profileID: UUID?) {
        let nextProfileID = enabled ? profileID : nil
        guard selectedProfileID != nextProfileID else { return }
        pollingTask?.cancel()
        pollingTask = nil
        selectedProfileID = nextProfileID
        lastObservedSignatures = nil
        lastSeenAppliedGeneration = controller.appliedGeneration
        errorMessage = nil

        guard nextProfileID != nil, let pollingInterval else { return }
        pollingTask = Task { @MainActor [weak self] in
            await self?.refreshNow()
            while !Task.isCancelled {
                do { try await Task.sleep(for: pollingInterval) }
                catch { return }
                guard !Task.isCancelled, self != nil else { return }
                await self?.refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard let profileID = selectedProfileID else { return }
        await gate.acquire()
        if Task.isCancelled || selectedProfileID != profileID {
            await gate.release()
            return
        }
        guard controller.health == .ready else {
            errorMessage = "Automatic saving is paused until the macOS Dock operation or recovery completes."
            await gate.release()
            return
        }
        do {
            observe(try backend.readCurrentTiles(), for: profileID)
        } catch {
            errorMessage = "Could not read the current macOS Dock: \(error.localizedDescription)"
        }
        await gate.release()
    }

    private func observe(_ tiles: [[String: Any]], for profileID: UUID) {
        guard selectedProfileID == profileID,
              store.state.settings.automaticallySaveNativeDockChanges,
              let profile = store.state.profiles.first(where: { $0.id == profileID && $0.kind == .native }) else { return }

        let imported = NativeDockSerializer.items(from: tiles)
        guard imported.count == tiles.count else {
            errorMessage = "The current macOS Dock has an item MyDock cannot save in a native profile. Automatic saving is paused."
            return
        }

        let signatures = NativeDockSerializer.signatures(from: imported)
        if controller.appliedGeneration != lastSeenAppliedGeneration {
            lastSeenAppliedGeneration = controller.appliedGeneration
            if signatures == controller.lastAppliedSignatures {
                lastObservedSignatures = signatures
                confirmSavedState()
                return
            }
        }
        guard let previous = lastObservedSignatures else {
            lastObservedSignatures = signatures
            confirmSavedState()
            return
        }
        guard signatures != previous else {
            confirmSavedState()
            return
        }
        lastObservedSignatures = signatures
        guard signatures != NativeDockSerializer.signatures(from: profile.items) else {
            confirmSavedState()
            return
        }

        store.replaceItems(NativeDockSerializer.preservingIDs(in: imported, from: profile.items), in: profileID)
        errorMessage = store.persistenceError
    }

    private func confirmSavedState() {
        // An unchanged Dock does not mean the last disk write succeeded.
        // Retry failed persistence and retain the warning until it really saves.
        if store.hasUnpersistedChanges { store.flush() }
        errorMessage = store.persistenceError
    }

    deinit { pollingTask?.cancel() }
}
