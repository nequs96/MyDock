import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

struct DockWindowDescriptor: Identifiable, Hashable, Sendable {
    var processID: pid_t
    var windowIndex: Int
    var bundleIdentifier: String
    var applicationName: String
    var title: String
    var isMinimized: Bool
    var accessibilityIdentifier: String?

    var id: String { "\(processID)-\(accessibilityIdentifier ?? "\(windowIndex):\(title)")" }
}

enum WindowAccessibilityService {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func requestAccessPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func shouldMinimizeFocusedApp(toggleEnabled: Bool,
                                        clickedBundleIdentifier: String?,
                                        frontmostBundleIdentifier: String?,
                                        hasFocusedWindow: Bool) -> Bool {
        toggleEnabled
            && clickedBundleIdentifier != nil
            && clickedBundleIdentifier == frontmostBundleIdentifier
            && hasFocusedWindow
    }

    static func windows() -> [DockWindowDescriptor] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [DockWindowDescriptor] = []
        let deadline = Date.now.addingTimeInterval(2)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            if Task.isCancelled || Date.now >= deadline { break }
            let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(applicationElement, 0.1)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }
            for (index, window) in windows.prefix(100).enumerated() {
                if Task.isCancelled || Date.now >= deadline { break }
                AXUIElementSetMessagingTimeout(window, 0.1)
                var titleValue: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var identifierValue: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(window, kAXIdentifierAttribute as CFString, &identifierValue)
                let identifier = (identifierValue as? String).flatMap { $0.isEmpty ? nil : $0 }
                var minimizedValue: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                let isMinimized = (minimizedValue as? NSNumber)?.boolValue ?? false
                result.append(DockWindowDescriptor(processID: app.processIdentifier,
                                                   windowIndex: index,
                                                   bundleIdentifier: bundleIdentifier,
                                                   applicationName: app.localizedName ?? bundleIdentifier,
                                                   title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                                                   isMinimized: isMinimized,
                                                   accessibilityIdentifier: identifier))
            }
        }
        return result.sorted {
            if $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) != .orderedSame {
                return $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    @discardableResult
    static func minimizeFocusedWindow(of bundleIdentifier: String) async -> Bool {
        await Task.detached(priority: .userInitiated) { minimizeFocusedWindowSynchronously(of: bundleIdentifier) }.value
    }

    private static func minimizeFocusedWindowSynchronously(of bundleIdentifier: String) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.2)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let focusedWindow = focusedWindow,
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return false }
        guard shouldMinimizeFocusedApp(toggleEnabled: true,
                                       clickedBundleIdentifier: bundleIdentifier,
                                       frontmostBundleIdentifier: app.bundleIdentifier,
                                       hasFocusedWindow: true) else { return false }
        // AX attribute values are opaque CF references; the type-ID guard above validates this bridge.
        let focusedWindowElement = focusedWindow as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedWindowElement, 0.2)
        var minimizeButton: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedWindowElement, kAXMinimizeButtonAttribute as CFString, &minimizeButton) == .success,
              let minimizeButton = minimizeButton,
              CFGetTypeID(minimizeButton) == AXUIElementGetTypeID() else { return false }
        AXUIElementSetMessagingTimeout(minimizeButton as! AXUIElement, 0.2)
        // The minimize-button value passed the same AXUIElement type-ID check.
        return AXUIElementPerformAction(minimizeButton as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func activate(_ descriptor: DockWindowDescriptor) {
        Task { @MainActor in
            let restored = await Task.detached(priority: .userInitiated) { activateSynchronously(descriptor) }.value
            if !restored {
                let alert = NSAlert()
                alert.messageText = "Window unavailable"
                alert.informativeText = "MyDock could not identify this window uniquely or the app did not respond. Open the app and choose its window directly, then try again."
                alert.runModal()
            }
        }
    }

    private static func activateSynchronously(_ descriptor: DockWindowDescriptor) -> Bool {
        guard AXIsProcessTrusted(), NSRunningApplication(processIdentifier: descriptor.processID)?.bundleIdentifier == descriptor.bundleIdentifier else { return false }
        let appElement = AXUIElementCreateApplication(descriptor.processID)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return false }
        let candidates = windows.prefix(100).map { window in
            AXUIElementSetMessagingTimeout(window, 0.1)
            return WindowRestoreCandidate(identifier: stringAttribute(kAXIdentifierAttribute, on: window),
                                          title: stringAttribute(kAXTitleAttribute, on: window) ?? "")
        }
        guard let index = WindowRestoreIdentity.match(identifier: descriptor.accessibilityIdentifier, title: descriptor.title, candidates: candidates) else { return false }
        let window = windows[index]
        var minimizedValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        if (minimizedValue as? NSNumber)?.boolValue == true {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return false }
        }
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        let activated = NSRunningApplication(processIdentifier: descriptor.processID)?.activate(options: [.activateIgnoringOtherApps]) == true
        return raised || activated
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
    private let previewCache: WindowPreviewDiskCache
    private let sampleWindows: @MainActor () async -> [DockWindowDescriptor]
    private let captureWindows: @MainActor ([DockWindowDescriptor], Set<String>) async -> WindowPreviewBatch
    private let canCapture: @MainActor () -> Bool

    init(previewCache: WindowPreviewDiskCache? = nil,
         sampleWindows: @escaping @MainActor () async -> [DockWindowDescriptor] = {
             let worker = Task.detached(priority: .utility) { WindowAccessibilityService.windows() }
             return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
         },
         captureWindows: @escaping @MainActor ([DockWindowDescriptor], Set<String>) async -> WindowPreviewBatch = {
             await WindowPreviewCapturer.captureVisibleWindows(descriptors: $0, freshIDs: $1)
         },
         canCapture: @escaping @MainActor () -> Bool = {
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
            if self.windows != sampled { self.windows = sampled }
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
            previewCache.removeAll()
            return
        }
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

struct WindowRestoreCandidate {
    var identifier: String?
    var title: String
}

enum WindowRestoreIdentity {
    static func match(identifier: String?, title: String, candidates: [WindowRestoreCandidate]) -> Int? {
        if let identifier {
            let matches = candidates.indices.filter { candidates[$0].identifier == identifier }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        let matches = candidates.indices.filter { candidates[$0].title == title }
        return matches.count == 1 ? matches[0] : nil
    }
}
