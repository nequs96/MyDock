import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// AX references identify the observed native object, including untitled windows.
/// The reference is immutable; AX messaging is performed only on worker tasks.
/// CF equality prevents a later same-title replacement receiving an old action.
final class WindowAccessibilityObservation: @unchecked Sendable, Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: WindowAccessibilityObservation, rhs: WindowAccessibilityObservation) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    /// Stable for one native window for as long as its app runs, unlike its index or title.
    var nativeHash: UInt { UInt(CFHash(element)) }
}

struct DockWindowDescriptor: Identifiable, Hashable, Sendable {
    var processID: pid_t
    var windowIndex: Int
    var bundleIdentifier: String
    var applicationName: String
    var title: String
    var isMinimized: Bool
    var accessibilityIdentifier: String?
    var rawTitle: String? = nil
    var applicationIdentity: NativeApplicationIdentity? = nil
    var accessibilityObservation: WindowAccessibilityObservation? = nil
    /// Set only when two different windows of one app share an AX hash, to keep their ids unique.
    var identityCollisionIndex: Int? = nil

    var identityTitle: String { rawTitle ?? title }
    /// The sampled AX object identifies the window, so focusing, reordering or retitling windows keeps
    /// their ids. `windowIndex` and the title are a fallback only for descriptors without an observation.
    var id: String {
        let lifetime = applicationIdentity.map { $0.launchDate.map { String($0.timeIntervalSince1970) } ?? "unknown" } ?? "legacy"
        let window = accessibilityIdentifier
            ?? accessibilityObservation.map { "ax\($0.nativeHash)" + (identityCollisionIndex.map { ":\($0)" } ?? "") }
            ?? "\(windowIndex):\(identityTitle)"
        return "\(processID)-\(lifetime)-\(window)"
    }
}

enum WindowIdentityPolicy {
    /// Distinct windows whose AX hashes collide fall back to their index, so ids stay unique within a sample.
    static func disambiguated(_ windows: [DockWindowDescriptor]) -> [DockWindowDescriptor] {
        var result = windows
        let groups = Dictionary(grouping: result.indices.filter { result[$0].accessibilityObservation != nil }) {
            result[$0].accessibilityObservation?.nativeHash ?? 0
        }
        for indices in groups.values where indices.count > 1 {
            for index in indices { result[index].identityCollisionIndex = result[index].windowIndex }
        }
        return result
    }
}

/// One background window sample. Apps that were slow or not reached before the deadline are listed,
/// so the monitor keeps their previous windows instead of dropping their tiles for a cycle.
struct WindowAccessibilitySample: Sendable {
    var windows: [DockWindowDescriptor]
    var incompleteProcessIDs: Set<pid_t> = []
}

enum WindowSampleMerge {
    static func merged(previous: [DockWindowDescriptor], sample: WindowAccessibilitySample) -> [DockWindowDescriptor] {
        guard !sample.incompleteProcessIDs.isEmpty else { return ordered(sample.windows) }
        let sampledProcesses = Set(sample.windows.map(\.processID))
        let retained = previous.filter {
            sample.incompleteProcessIDs.contains($0.processID) && !sampledProcesses.contains($0.processID)
        }
        return ordered(sample.windows + retained)
    }

    static func ordered(_ windows: [DockWindowDescriptor]) -> [DockWindowDescriptor] {
        windows.sorted {
            let order = $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName)
            return order == .orderedSame ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending : order == .orderedAscending
        }
    }
}

enum WindowAccessibilityService {
    static func isTrusted() -> Bool { AppRuntimeEnvironment.allowsNativeEffects && AXIsProcessTrusted() }

    static func requestAccessPrompt() -> Bool {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return false }
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    enum WindowDiscoveryResult: Sendable {
        case available([DockWindowDescriptor])
        case permissionRequired
        case applicationUnavailable
        case unavailable
    }

    enum WindowMenuAction: Sendable, Equatable { case activate, close }
    @MainActor private static var menuDiscoveryTask: Task<Void, Never>?

    /// Explicit menu discovery is independent of background tile/minimize monitoring.
    /// No permission request occurs here. The chooser contains fresh observations,
    /// each revalidated again when its action is requested.
    @MainActor
    static func showWindowMenu(for identity: NativeApplicationIdentity, action: WindowMenuAction) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let location = NSEvent.mouseLocation
        menuDiscoveryTask?.cancel()
        menuDiscoveryTask = Task {
            let signpost = PerformanceSignposts.begin("WindowDiscovery")
            let worker = Task.detached(priority: .userInitiated) { discoverWindows(for: identity) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            PerformanceSignposts.end("WindowDiscovery", signpost)
            guard !Task.isCancelled else { return }
            switch result {
            case .available(let windows):
                guard currentApplication(matches: identity) != nil else {
                    showDiscoveryMessage("Application unavailable", "The selected application stopped or restarted. Open its current menu and try again.")
                    return
                }
                guard !windows.isEmpty else {
                    showDiscoveryMessage("No accessible windows", "This application has no windows that macOS Accessibility currently exposes.")
                    return
                }
                let menu = NSMenu(title: action == .close ? "Close Window" : "Windows")
                let targets = windows.map { descriptor in
                    WindowMenuTarget(descriptor: descriptor, action: action)
                }
                for target in targets {
                    let title = action == .close ? target.descriptor.title
                        : "\(target.descriptor.isMinimized ? "Restore" : "Activate"): \(target.descriptor.title)"
                    let item = NSMenuItem(title: title, action: #selector(WindowMenuTarget.performAction(_:)), keyEquivalent: "")
                    item.target = target
                    menu.addItem(item)
                }
                // AppKit targets are weak. Keep every target alive while this menu tracks.
                withExtendedLifetime(targets) { _ = menu.popUp(positioning: nil, at: location, in: nil) }
            case .permissionRequired:
                showDiscoveryMessage("Accessibility access needed", "Window actions need MyDock’s Accessibility access. Allow it in System Settings → Privacy & Security → Accessibility, then try again. Opening apps does not require this access.")
            case .applicationUnavailable:
                showDiscoveryMessage("Application unavailable", "The selected application stopped or restarted. Open its current menu and try again.")
            case .unavailable:
                showDiscoveryMessage("Windows unavailable", "The application did not provide a complete window list in time. Try again, or select its window directly in the application.")
            }
        }
    }

    @MainActor
    private static func showDiscoveryMessage(_ title: String, _ message: String) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        DockModal.run(alert)
    }

    @MainActor
    private final class WindowMenuTarget: NSObject {
        let descriptor: DockWindowDescriptor
        let action: WindowMenuAction
        init(descriptor: DockWindowDescriptor, action: WindowMenuAction) {
            self.descriptor = descriptor
            self.action = action
        }
        @objc func performAction(_ sender: NSMenuItem) {
            switch action {
            case .activate: WindowAccessibilityService.activate(descriptor)
            case .close: WindowAccessibilityService.close(descriptor)
            }
        }
    }

    static func currentApplication(matches identity: NativeApplicationIdentity) -> NSRunningApplication? {
        guard AppRuntimeEnvironment.allowsNativeEffects, let app = NSRunningApplication(processIdentifier: identity.processID),
              let current = NativeApplicationIdentity.observing(app), identity.matches(current) else { return nil }
        return app
    }

    static func discoverWindows(for identity: NativeApplicationIdentity, timeLimit: TimeInterval = 2) -> WindowDiscoveryResult {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return .unavailable }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        guard let app = currentApplication(matches: identity) else { return .applicationUnavailable }
        return observedWindows(for: app, identity: identity, deadline: Date.now.addingTimeInterval(timeLimit))
    }

    static func windows() -> WindowAccessibilitySample {
        guard AppRuntimeEnvironment.allowsNativeEffects, AXIsProcessTrusted() else { return WindowAccessibilitySample(windows: []) }
        var result: [DockWindowDescriptor] = []
        var incomplete = Set<pid_t>()
        let deadline = Date.now.addingTimeInterval(2)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            if Task.isCancelled || Date.now >= deadline {
                incomplete.insert(app.processIdentifier)
                continue
            }
            guard let identity = NativeApplicationIdentity.observing(app) else { continue }
            switch observedWindows(for: app, identity: identity, deadline: deadline) {
            case .available(let windows): result += windows
            case .unavailable: incomplete.insert(identity.processID)
            case .permissionRequired, .applicationUnavailable: break
            }
        }
        return WindowAccessibilitySample(windows: WindowSampleMerge.ordered(result), incompleteProcessIDs: incomplete)
    }

    /// The Accessibility messaging timeout for the next call: at most 0.1 s and never past `deadline`,
    /// so a slow app cannot hold a scan (or the context menu that waits for it) beyond its bound.
    static func messagingTimeout(until deadline: Date, now: Date = .now) -> Float {
        Float(max(0.01, min(0.1, deadline.timeIntervalSince(now))))
    }

    private static func observedWindows(for app: NSRunningApplication, identity: NativeApplicationIdentity, deadline: Date) -> WindowDiscoveryResult {
        let applicationElement = AXUIElementCreateApplication(identity.processID)
        AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout(until: deadline))
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], windows.count <= 100 else { return .unavailable }
        var result: [DockWindowDescriptor] = []
        for (index, window) in windows.enumerated() {
            guard !Task.isCancelled, Date.now < deadline else { return .unavailable }
            AXUIElementSetMessagingTimeout(window, messagingTimeout(until: deadline))
            guard let rawTitle = windowTitle(on: window), Date.now < deadline else { return .unavailable }
            AXUIElementSetMessagingTimeout(window, messagingTimeout(until: deadline))
            let identifier = stringAttribute(kAXIdentifierAttribute, on: window).flatMap { $0.isEmpty ? nil : $0 }
            guard Date.now < deadline else { return .unavailable }
            AXUIElementSetMessagingTimeout(window, messagingTimeout(until: deadline))
            var minimizedValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let displayTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(DockWindowDescriptor(processID: identity.processID, windowIndex: index,
                bundleIdentifier: identity.bundleIdentifier, applicationName: app.localizedName ?? identity.bundleIdentifier,
                title: displayTitle.isEmpty ? (app.localizedName ?? "Window") : displayTitle,
                isMinimized: (minimizedValue as? NSNumber)?.boolValue ?? false,
                accessibilityIdentifier: identifier, rawTitle: rawTitle, applicationIdentity: identity,
                accessibilityObservation: WindowAccessibilityObservation(window)))
        }
        guard !Task.isCancelled, Date.now < deadline else { return .unavailable }
        guard currentApplication(matches: identity) != nil else { return .applicationUnavailable }
        return .available(WindowIdentityPolicy.disambiguated(result))
    }

    @discardableResult
    static func minimizeFocusedWindow(of identity: NativeApplicationIdentity) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard AppRuntimeEnvironment.allowsNativeEffects, AXIsProcessTrusted(), currentApplication(matches: identity) != nil,
                  let app = NSWorkspace.shared.frontmostApplication,
                  let frontmost = NativeApplicationIdentity.observing(app), identity.matches(frontmost) else { return false }
            let applicationElement = AXUIElementCreateApplication(identity.processID)
            AXUIElementSetMessagingTimeout(applicationElement, 0.2)
            var focusedWindow: CFTypeRef?
            guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
                  let focusedWindow, CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return false }
            let focusedWindowElement = focusedWindow as! AXUIElement
            AXUIElementSetMessagingTimeout(focusedWindowElement, 0.2)
            var minimizeButton: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focusedWindowElement, kAXMinimizeButtonAttribute as CFString, &minimizeButton) == .success,
                  let minimizeButton, CFGetTypeID(minimizeButton) == AXUIElementGetTypeID(),
                  currentApplication(matches: identity) != nil else { return false }
            AXUIElementSetMessagingTimeout(minimizeButton as! AXUIElement, 0.2)
            return AXUIElementPerformAction(minimizeButton as! AXUIElement, kAXPressAction as CFString) == .success
        }.value
    }

    static func activate(_ descriptor: DockWindowDescriptor) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        Task { @MainActor in
            let restored = await Task.detached(priority: .userInitiated) { restoreSynchronously(descriptor) }.value
            if restored, let identity = descriptor.applicationIdentity, let app = currentApplication(matches: identity) {
                // Unminimizing and raising select the window; bringing its app forward is best effort,
                // since macOS may decline a cooperative activation request.
                AppActivation.activate(app)
                return
            }
            if AppRuntimeEnvironment.allowsNativeEffects {
                let alert = NSAlert()
                alert.messageText = "Window unavailable"
                alert.informativeText = "MyDock could not identify this window uniquely or the app did not respond. Open the app and choose its window directly, then try again."
                DockModal.run(alert)
            }
        }
    }

    static func close(_ descriptor: DockWindowDescriptor) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        Task { @MainActor in
            // AXPress acknowledges the normal close request, not the document
            // dialog outcome. The target app owns Save/Cancel and its lifetime.
            let requestAccepted = await Task.detached(priority: .userInitiated) {
                guard let window = resolvedWindow(descriptor) else { return false }
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
                      let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                      let identity = descriptor.applicationIdentity, currentApplication(matches: identity) != nil else { return false }
                let button = value as! AXUIElement
                AXUIElementSetMessagingTimeout(button, 0.2)
                guard isTrusted(), currentApplication(matches: identity) != nil else { return false }
                return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            }.value
            if !requestAccepted, AppRuntimeEnvironment.allowsNativeEffects {
                let alert = NSAlert()
                alert.messageText = "Could not close window"
                alert.informativeText = "Check MyDock’s Accessibility access, or open the app and close the window directly. The window may no longer be available."
                DockModal.run(alert)
            }
        }
    }

    private static func resolvedWindow(_ descriptor: DockWindowDescriptor) -> AXUIElement? {
        guard AppRuntimeEnvironment.allowsNativeEffects, AXIsProcessTrusted(), let identity = descriptor.applicationIdentity,
              descriptor.processID == identity.processID, descriptor.bundleIdentifier == identity.bundleIdentifier,
              let observation = descriptor.accessibilityObservation,
              currentApplication(matches: identity) != nil else { return nil }
        let appElement = AXUIElementCreateApplication(descriptor.processID)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], windows.count <= 100 else { return nil }
        // The sampled native AX object is the identity. Titles change constantly
        // (browser tabs, documents), so they are never required to match here.
        let sameObject = windows.indices.filter { CFEqual(observation.element, windows[$0]) }
        guard !Task.isCancelled,
              let index = WindowRestoreIdentity.uniqueIndex(sameObject),
              currentApplication(matches: identity) != nil else { return nil }
        // Elements read from an attribute do not inherit the application's timeout; a hung app
        // must not hold a window action for the 6 s default.
        AXUIElementSetMessagingTimeout(windows[index], 0.2)
        return windows[index]
    }

    /// Unminimizes and raises the window. Activating its app happens on the main actor afterwards.
    private static func restoreSynchronously(_ descriptor: DockWindowDescriptor) -> Bool {
        guard let window = resolvedWindow(descriptor), let identity = descriptor.applicationIdentity,
              currentApplication(matches: identity) != nil else { return false }
        var minimizedValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        guard isTrusted(), currentApplication(matches: identity) != nil else { return false }
        if (minimizedValue as? NSNumber)?.boolValue == true {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return false }
        }
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        // Application activation alone is not successful window selection.
        return raised && currentApplication(matches: identity) != nil
    }

    /// Untitled windows are common (no title attribute value). Only a failed or
    /// timed-out read is incomplete data; an absent title is an honest empty title.
    private static func windowTitle(on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) {
        case .success: return (value as? String) ?? ""
        case .noValue, .attributeUnsupported: return ""
        default: return nil
        }
    }

    private static func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

@MainActor
final class WindowAccessibilityMonitor: ObservableObject {
    static let shared = WindowAccessibilityMonitor()

    @Published private(set) var windows: [DockWindowDescriptor] = []
    @Published private(set) var previews: [String: NSImage] = [:]
    private var refreshTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?
    private var sampleGeneration = UUID()
    private var previewCaptureTask: Task<Void, Never>?
    private var previewCaptureGeneration = UUID()
    private var previewAttemptedAt: [String: Date] = [:]
    private var previewAttemptKeys: [String: String] = [:]
    private var previewStoredAt: [String: Date] = [:]
    private var previewImageKeys: [String: String] = [:]
    private var lastPreviewBatchAt: Date?
    private var wantsMonitor = false
    private var wantsPreviews = false
    private var retainsPreviews = false
    private var previewRetentionPolicyApplied = false
    /// Set once the cache was purged for a missing Screen Recording permission, so the 4 s refresh
    /// does not enumerate the cache directory again until capture is possible.
    private var previewCacheClearedForMissingPermission = false
    private let previewCache: WindowPreviewDiskCache
    private let sampleWindows: @MainActor () async -> WindowAccessibilitySample
    private let captureWindows: @MainActor ([DockWindowDescriptor], Set<String>) async -> WindowPreviewBatch
    private let canCapture: @MainActor () -> Bool

    init(previewCache: WindowPreviewDiskCache? = nil,
         sampleWindows: @escaping @MainActor () async -> WindowAccessibilitySample = {
             let worker = Task.detached(priority: .utility) { WindowAccessibilityService.windows() }
             return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
         },
         captureWindows: @escaping @MainActor ([DockWindowDescriptor], Set<String>) async -> WindowPreviewBatch = {
             await WindowPreviewCapturer.captureVisibleWindows(descriptors: $0, freshIDs: $1)
         },
         canCapture: @escaping @MainActor () -> Bool = {
             guard AppRuntimeEnvironment.allowsNativeEffects else { return false }
             if #available(macOS 14.0, *) { return CGPreflightScreenCaptureAccess() }
             return false
         }) {
        self.previewCache = previewCache ?? WindowPreviewDiskCache()
        self.sampleWindows = sampleWindows
        self.captureWindows = captureWindows
        self.canCapture = canCapture
    }

    func setPreviewCacheRetentionEnabled(_ enabled: Bool) {
        guard !previewRetentionPolicyApplied || enabled != retainsPreviews else { return }
        previewRetentionPolicyApplied = true
        retainsPreviews = enabled
        if enabled {
            // Recheck expiry when the user enables preview caching.
            previewCache.pruneExpired()
            if !canCapture() { previewCache.removeAll() }
        } else {
            previewCache.removeAll()
            previews = [:]
            previewStoredAt = [:]
            previewImageKeys = [:]
        }
    }

    func setEnabled(_ enabled: Bool, previewsEnabled: Bool = false) {
        let activePreviews = enabled && previewsEnabled
        guard enabled != wantsMonitor || activePreviews != wantsPreviews else { return }
        let wasEnabled = wantsMonitor
        wantsMonitor = enabled
        wantsPreviews = activePreviews
        if !activePreviews {
            stopPreviewCapture()
            previewAttemptedAt = [:]
            previewAttemptKeys = [:]
            previewStoredAt = [:]
            previewImageKeys = [:]
            lastPreviewBatchAt = nil
            previews = [:]
        }
        guard enabled else {
            sampleGeneration = UUID()
            sampleTask?.cancel()
            sampleTask = nil
            refreshTask?.cancel()
            refreshTask = nil
            windows = []
            return
        }
        if !wasEnabled {
            refresh()
            refreshTask = Task { [weak self] in
                for await _ in RefreshScheduler.shared.ticks(every: 4) {
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            }
        } else if activePreviews {
            refresh()
        }
    }

    func preview(for window: DockWindowDescriptor) -> NSImage? { previews[window.id] }

    func refresh() {
        guard wantsMonitor, sampleTask == nil else { return }
        let generation = sampleGeneration
        let sampler = sampleWindows
        sampleTask = Task { [weak self] in
            let sampled = await sampler()
            guard let self, !Task.isCancelled, self.sampleGeneration == generation, self.wantsMonitor else { return }
            self.sampleTask = nil
            let merged = WindowSampleMerge.merged(previous: self.windows, sample: sampled)
            // Without previews only minimized windows matter (they are the Dock tiles), so title churn in
            // other windows publishes nothing. Previews also need the visible windows they capture.
            if self.windows != merged,
               self.wantsPreviews || self.windows.filter(\.isMinimized) != merged.filter(\.isMinimized) {
                self.windows = merged
            }
            self.refreshPreviews()
        }
    }

    private func refreshPreviews() {
        guard wantsPreviews else { return }
        let currentIDs = Set(windows.map(\.id))
        let cacheKeys = WindowPreviewCacheIdentity.uniqueKeys(for: windows)
        let now = Date.now
        previews = previews.filter { id, _ in
            guard currentIDs.contains(id), cacheKeys[id] != nil, cacheKeys[id] == previewImageKeys[id],
                  let storedAt = previewStoredAt[id] else { return false }
            let age = now.timeIntervalSince(storedAt)
            return age >= 0 && age <= WindowPreviewDiskCache.maximumAge
        }
        previewStoredAt = previewStoredAt.filter { id, _ in previews[id] != nil }
        previewImageKeys = previewImageKeys.filter { previews[$0.key] != nil }
        previewAttemptedAt = previewAttemptedAt.filter { currentIDs.contains($0.key) && cacheKeys[$0.key] == previewAttemptKeys[$0.key] }
        previewAttemptKeys = previewAttemptKeys.filter { previewAttemptedAt[$0.key] != nil }
        guard canCapture() else {
            stopPreviewCapture()
            previews = [:]
            previewStoredAt = [:]
            previewImageKeys = [:]
            previewAttemptedAt = [:]
            previewAttemptKeys = [:]
            if !previewCacheClearedForMissingPermission {
                previewCacheClearedForMissingPermission = true
                previewCache.removeAll()
            }
            return
        }
        previewCacheClearedForMissingPermission = false
        for descriptor in windows where descriptor.isMinimized {
            guard previews[descriptor.id] == nil,
                  let key = cacheKeys[descriptor.id],
                  let cached = previewCache.preview(for: key) else { continue }
            previews[descriptor.id] = cached.image
            previewStoredAt[descriptor.id] = cached.storedAt
            previewImageKeys[descriptor.id] = key
        }
        guard previewCaptureTask == nil else {
            return
        }
        guard lastPreviewBatchAt.map({ now.timeIntervalSince($0) >= 8 }) ?? true else { return }
        lastPreviewBatchAt = now
        let freshIDs = Set(previewAttemptedAt.compactMap { id, attemptedAt in
            now.timeIntervalSince(attemptedAt) < 30 ? id : nil
        })
        let descriptors = windows
        let capture = captureWindows
        let generation = UUID()
        previewCaptureGeneration = generation
        previewCaptureTask = Task { [weak self] in
            let batch = await capture(descriptors, freshIDs)
            guard let self, self.previewCaptureGeneration == generation else { return }
            self.previewCaptureTask = nil
            guard !Task.isCancelled, self.wantsMonitor, self.wantsPreviews else { return }
            guard self.canCapture() else { self.refreshPreviews(); return }
            let validIDs = Set(self.windows.map(\.id))
            let currentCacheKeys = WindowPreviewCacheIdentity.uniqueKeys(for: self.windows)
            var updated = self.previews
            for id in batch.attemptedIDs where validIDs.contains(id) && cacheKeys[id] != nil && cacheKeys[id] == currentCacheKeys[id] {
                self.previewAttemptedAt[id] = .now
                self.previewAttemptKeys[id] = cacheKeys[id]
            }
            for (id, image) in batch.images where validIDs.contains(id) && cacheKeys[id] != nil && cacheKeys[id] == currentCacheKeys[id] {
                updated[id] = image
                self.previewStoredAt[id] = .now
                self.previewImageKeys[id] = cacheKeys[id]
                if self.retainsPreviews, let key = currentCacheKeys[id] {
                    self.previewCache.store(image, for: key)
                }
            }
            self.previews = updated
        }
    }

    private func stopPreviewCapture() {
        previewCaptureGeneration = UUID()
        previewCaptureTask?.cancel()
        previewCaptureTask = nil
    }

    deinit {
        refreshTask?.cancel()
        sampleTask?.cancel()
        previewCaptureTask?.cancel()
    }
}

enum WindowRestoreIdentity {
    /// A native-object match is usable only when exactly one live window has it; titles are never used.
    static func uniqueIndex(_ matches: [Int]) -> Int? { matches.count == 1 ? matches[0] : nil }
}
