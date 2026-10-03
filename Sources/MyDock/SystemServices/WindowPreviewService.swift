import AppKit
import CoreGraphics
import ScreenCaptureKit

struct WindowPreviewCandidate {
    var windowID: CGWindowID
    var processID: pid_t
    var title: String
    var isOnScreen: Bool
    var width: CGFloat
    var height: CGFloat
}

struct WindowPreviewBatch {
    var images: [String: NSImage] = [:]
    var attemptedIDs: Set<String> = []
}

enum WindowPreviewMatchingPolicy {
    private struct Key: Hashable {
        var processID: pid_t
        var title: String
    }

    static func matchedWindowIDs(descriptors: [DockWindowDescriptor],
                                 candidates: [WindowPreviewCandidate]) -> [String: CGWindowID] {
        let eligibleDescriptors = descriptors.filter { !$0.isMinimized && !$0.identityTitle.isEmpty }
        let eligibleCandidates = candidates.filter {
            $0.isOnScreen && $0.width.isFinite && $0.height.isFinite && $0.width >= 40 && $0.height >= 40
                && !$0.title.isEmpty
        }
        let byDescriptorKey = Dictionary(grouping: eligibleDescriptors) {
            Key(processID: $0.processID, title: normalizedTitle($0.identityTitle))
        }
        let byCandidateKey = Dictionary(grouping: eligibleCandidates) {
            Key(processID: $0.processID, title: normalizedTitle($0.title))
        }

        var matches: [String: CGWindowID] = [:]
        for (key, sampledWindows) in byDescriptorKey {
            guard sampledWindows.count == 1,
                  let shareableWindows = byCandidateKey[key], shareableWindows.count == 1 else { continue }
            matches[sampledWindows[0].id] = shareableWindows[0].windowID
        }
        return matches
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}

@MainActor
enum WindowPreviewCapturer {
    static func captureVisibleWindows(descriptors: [DockWindowDescriptor],
                                      freshIDs: Set<String>) async -> WindowPreviewBatch {
        guard AppRuntimeEnvironment.allowsNativeEffects, #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(), !Task.isCancelled else {
            return WindowPreviewBatch()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let shareableWindows = content.windows.filter { $0.windowLayer == 0 && $0.owningApplication != nil }
            let candidates = shareableWindows.compactMap { window -> WindowPreviewCandidate? in
                guard let app = window.owningApplication else { return nil }
                return WindowPreviewCandidate(windowID: window.windowID,
                                              processID: app.processID,
                                              title: window.title ?? "",
                                              isOnScreen: window.isOnScreen,
                                              width: window.frame.width,
                                              height: window.frame.height)
            }
            let matches = WindowPreviewMatchingPolicy.matchedWindowIDs(descriptors: descriptors,
                                                                         candidates: candidates)
            var windowsByID: [CGWindowID: SCWindow] = [:]
            for window in shareableWindows { windowsByID[window.windowID] = window }

            var batch = WindowPreviewBatch()
            for descriptor in descriptors {
                guard batch.attemptedIDs.count < 4 else { break }
                guard !Task.isCancelled else { break }
                guard !freshIDs.contains(descriptor.id),
                      let windowID = matches[descriptor.id],
                      let window = windowsByID[windowID] else { continue }
                batch.attemptedIDs.insert(descriptor.id)
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let longestSide = max(window.frame.width, window.frame.height)
                let scale = min(1, 192 / longestSide)
                configuration.width = max(1, Int((window.frame.width * scale).rounded()))
                configuration.height = max(1, Int((window.frame.height * scale).rounded()))
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.showsCursor = false
                do {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                           configuration: configuration)
                    guard !Task.isCancelled else { break }
                    batch.images[descriptor.id] = NSImage(cgImage: image,
                                                          size: NSSize(width: configuration.width,
                                                                       height: configuration.height))
                } catch {
                    // Some windows cannot be captured; their app icon remains the tile fallback.
                }
            }
            return batch
        } catch {
            return WindowPreviewBatch()
        }
    }
}
