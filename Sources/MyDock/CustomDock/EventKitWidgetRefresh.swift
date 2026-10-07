import AppKit
import Combine
import EventKit
import SwiftUI

// MARK: - Coalesced EventKit refresh

/// The `.task(id:)` key of an EventKit view: its own settings plus the shared change generation.
private struct EventKitRefreshKey<Value: Equatable>: Equatable {
    var value: Value
    var generation: Int
}

extension View {
    /// The one EventKit refresh every Calendar and Reminders view uses: on appear, whenever `scope` changes, once per
    /// coalesced EventKit, activation or wake signal, and every five minutes while visible. It ends with the view.
    @MainActor
    func eventKitRefresh<Scope: Equatable>(scope: Scope, perform: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(EventKitRefreshModifier(scope: scope, perform: perform))
    }
}

/// Main-actor isolated explicitly: it reads the main-actor change monitor and refresh scheduler.
@MainActor
private struct EventKitRefreshModifier<Scope: Equatable>: ViewModifier {
    var scope: Scope
    var perform: @MainActor @Sendable () async -> Void
    @ObservedObject private var changes = EventKitChangeMonitor.shared

    func body(content: Content) -> some View {
        content.task(id: EventKitRefreshKey(value: scope, generation: changes.generation)) {
            await perform()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await perform()
            }
        }
    }
}

/// The current saved configuration of one widget, shared by the views that re-read it after an await.
@MainActor
enum WidgetConfigurationLookup {
    /// The item's configuration as the store holds it now, or nil when the item or its Dock is gone.
    static func current(store: ProfileStore, itemID: UUID, profileID: UUID) -> WidgetConfiguration? {
        guard let item = store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == itemID }) else { return nil }
        return item.widgetConfiguration ?? WidgetConfiguration()
    }

    /// Why a configuration change was refused, or nil when it was kept or changed nothing.
    nonisolated static func rejection(_ result: WidgetConfigurationUpdateResult) -> String? {
        if case .rejected(let message) = result { return message }
        return nil
    }
}

/// One shared signal for every Calendar and Reminders view. EventKit store changes arrive in bursts during iCloud
/// sync, and app activation and wake follow each other, so the views refetch once per burst instead of once per
/// notification. While nothing visible wants refreshes (the Dock is hidden and no popout is open), the signal waits
/// for the scheduler's next active tick instead of fetching for a Dock nobody sees.
@MainActor
final class EventKitChangeMonitor: ObservableObject {
    static let shared = EventKitChangeMonitor()

    /// Increments once per coalesced burst; views use it in `.task(id:)`.
    @Published private(set) var generation = 0
    private let delay: Duration
    private let scheduler: RefreshScheduler
    private var observations: [AnyCancellable] = []
    private var pending: Task<Void, Never>?

    init(delay: Duration = .seconds(1), center: NotificationCenter = .default,
         workspaceCenter: NotificationCenter? = nil, scheduler: RefreshScheduler? = nil) {
        self.delay = delay
        self.scheduler = scheduler ?? .shared
        let publishers = [
            center.publisher(for: .EKEventStoreChanged),
            center.publisher(for: NSApplication.didBecomeActiveNotification),
            (workspaceCenter ?? NSWorkspace.shared.notificationCenter).publisher(for: NSWorkspace.didWakeNotification)
        ]
        // EKEventStoreChanged may be posted off the main thread, so each signal hops to the main actor.
        observations = publishers.map { publisher in
            publisher.sink { @Sendable [weak self] _ in
                Task { @MainActor in self?.signal() }
            }
        }
    }

    /// Restarts the coalescing window; the generation advances once the window passes without another signal.
    func signal() {
        pending?.cancel()
        pending = Task { [weak self, delay, scheduler] in
            do { try await Task.sleep(for: delay) } catch { return }
            if !scheduler.isActive {
                // The scheduler only ticks while active, so the first tick marks the Dock or a popout becoming visible.
                for await _ in scheduler.ticks(every: 1) { break }
            }
            guard !Task.isCancelled, let self else { return }
            self.generation &+= 1
            self.pending = nil
        }
    }
}
