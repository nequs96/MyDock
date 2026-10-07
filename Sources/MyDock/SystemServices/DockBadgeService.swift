import AppKit
import ApplicationServices
import Combine
import Foundation

struct DockBadgeEntry: Equatable, Sendable {
    var bundleIdentifier: String
    var statusLabel: String
}

enum DockBadgeValuePolicy {
    static func visibleLabel(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let number = Int(value) {
            guard number > 0 else { return nil }
            if number > 999 { return "999+" }
            return String(number)
        }
        // A long label is shortened with an ellipsis so it reads as truncated, not as a typo.
        return value.count > 8 ? String(value.prefix(7)) + "…" : value
    }

    static func badges(from entries: [DockBadgeEntry]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            guard !entry.bundleIdentifier.isEmpty,
                  result[entry.bundleIdentifier] == nil,
                  let label = visibleLabel(entry.statusLabel) else { continue }
            result[entry.bundleIdentifier] = label
        }
        return result
    }
}

enum DockBadgeReader {
    private static let maximumElements = 300
    private static let maximumDepth = 7

    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    static func read() -> [String: String] {
        guard isSupported, AppRuntimeEnvironment.allowsNativeEffects, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var pending: [(element: AXUIElement, depth: Int)] = [(application, 0)]
        var entries: [DockBadgeEntry] = []
        var visited = 0

        while let current = pending.popLast(), visited < maximumElements {
            visited += 1
            if stringAttribute("AXRole", on: current.element) == "AXApplicationDockItem",
               let bundleIdentifier = bundleIdentifierAttribute(on: current.element),
               let status = stringAttribute("AXStatusLabel", on: current.element) {
                entries.append(DockBadgeEntry(bundleIdentifier: bundleIdentifier, statusLabel: status))
            }
            guard current.depth < maximumDepth else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current.element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                // Children do not inherit the application element's timeout; a stalled Dock must not hold
                // each read for the 6 s default.
                AXUIElementSetMessagingTimeout(child, 0.1)
                pending.append((element: child, depth: current.depth + 1))
            }
        }
        return DockBadgeValuePolicy.badges(from: entries)
    }

    private static func bundleIdentifierAttribute(on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success else { return nil }
        let url: URL?
        if let value = value as? URL {
            url = value
        } else if let value = value as? String {
            if value.hasPrefix("/") {
                url = URL(fileURLWithPath: value)
            } else {
                url = URL(string: value)
            }
        } else {
            url = nil
        }
        guard let url, url.isFileURL, let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return nil }
        return bundleIdentifier
    }

    private static func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

@MainActor
final class DockBadgeMonitor: ObservableObject {
    static let shared = DockBadgeMonitor()

    @Published private(set) var badges: [String: String] = [:]
    private var isEnabled = false
    private var dockIsVisible = false
    private var refreshTask: Task<Void, Never>?

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        synchronizeRefreshTask()
    }

    func setDockVisible(_ visible: Bool) {
        guard dockIsVisible != visible else { return }
        dockIsVisible = visible
        synchronizeRefreshTask()
    }

    private func synchronizeRefreshTask() {
        refreshTask?.cancel()
        refreshTask = nil
        guard isEnabled, dockIsVisible, DockBadgeReader.isSupported else {
            badges = [:]
            return
        }
        refreshTask = Task { [weak self] in
            await self?.readBadges()
            // The shared scheduler coalesces this poll with other refreshes and pauses it while away.
            for await _ in RefreshScheduler.shared.ticks(every: 5) {
                guard !Task.isCancelled, let self else { return }
                await self.readBadges()
            }
        }
    }

    private func readBadges() async {
        let latest = await Task.detached(priority: .utility) { DockBadgeReader.read() }.value
        guard !Task.isCancelled else { return }
        badges = latest
    }
}
