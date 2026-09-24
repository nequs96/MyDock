import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

struct DockWindowDescriptor: Identifiable, Hashable {
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
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }
            for (index, window) in windows.enumerated() {
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
    static func minimizeFocusedWindow(of bundleIdentifier: String) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
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
        var minimizeButton: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedWindowElement, kAXMinimizeButtonAttribute as CFString, &minimizeButton) == .success,
              let minimizeButton = minimizeButton,
              CFGetTypeID(minimizeButton) == AXUIElementGetTypeID() else { return false }
        // The minimize-button value passed the same AXUIElement type-ID check.
        return AXUIElementPerformAction(minimizeButton as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func activate(_ descriptor: DockWindowDescriptor) {
        guard AXIsProcessTrusted() else { return }
        let appElement = AXUIElementCreateApplication(descriptor.processID)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }
        var window = descriptor.accessibilityIdentifier.flatMap { identifier in
            windows.first { stringAttribute(kAXIdentifierAttribute, on: $0) == identifier }
        } ?? windows.first(where: { stringAttribute(kAXTitleAttribute, on: $0) == descriptor.title })
        if window == nil, windows.indices.contains(descriptor.windowIndex) {
            window = windows[descriptor.windowIndex]
        }
        guard let window else { return }
        var minimizedValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        if (minimizedValue as? NSNumber)?.boolValue == true {
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: descriptor.processID)?.activate(options: [.activateIgnoringOtherApps])
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
    private var previewCaptureTask: Task<Void, Never>?
    private var previewAttemptedAt: [String: Date] = [:]
    private var lastPreviewBatchAt: Date?
    private var wantsMonitor = false
    private var wantsPreviews = false

    func setEnabled(_ enabled: Bool, previewsEnabled: Bool = false) {
        let activePreviews = enabled && previewsEnabled
        guard enabled != wantsMonitor || activePreviews != wantsPreviews else { return }
        let wasEnabled = wantsMonitor
        wantsMonitor = enabled
        wantsPreviews = activePreviews
        if !activePreviews {
            previewCaptureTask?.cancel()
            previewCaptureTask = nil
            previewAttemptedAt = [:]
            lastPreviewBatchAt = nil
            previews = [:]
        }
        guard enabled else {
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
        guard wantsMonitor else { return }
        windows = WindowAccessibilityService.windows()
        guard wantsPreviews else { return }
        let currentIDs = Set(windows.map(\.id))
        previews = previews.filter { currentIDs.contains($0.key) }
        previewAttemptedAt = previewAttemptedAt.filter { currentIDs.contains($0.key) }
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(), previewCaptureTask == nil else {
            return
        }
        let now = Date.now
        guard lastPreviewBatchAt.map({ now.timeIntervalSince($0) >= 8 }) ?? true else { return }
        lastPreviewBatchAt = now
        let freshIDs = Set(previewAttemptedAt.compactMap { id, attemptedAt in
            now.timeIntervalSince(attemptedAt) < 30 ? id : nil
        })
        let descriptors = windows
        previewCaptureTask = Task { [weak self] in
            let batch = await WindowPreviewCapturer.captureVisibleWindows(descriptors: descriptors,
                                                                           freshIDs: freshIDs)
            guard let self else { return }
            self.previewCaptureTask = nil
            guard self.wantsMonitor, self.wantsPreviews else { return }
            let validIDs = Set(self.windows.map(\.id))
            var updated = self.previews
            for id in batch.attemptedIDs where validIDs.contains(id) {
                self.previewAttemptedAt[id] = .now
            }
            for (id, image) in batch.images where validIDs.contains(id) {
                updated[id] = image
            }
            self.previews = updated
        }
    }
}
