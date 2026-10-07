import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
protocol DockSwitchFreezeProviding {
    func beginIfEnabled() async -> UUID?
    func end(_ sessionID: UUID)
}

@MainActor
final class NoDockSwitchFreezeProvider: DockSwitchFreezeProviding {
    func beginIfEnabled() async -> UUID? { nil }
    func end(_ sessionID: UUID) {}
}

@MainActor
final class ScreenCaptureDockSwitchFreezeProvider: DockSwitchFreezeProviding {
    private struct Session {
        var windows: [NSWindow]
        var timeout: Task<Void, Never>?
    }

    /// The overlay ignores input, so it never outlives a normal Dock relaunch for long, even when the
    /// switch is slow or fails and rolls back.
    static let maximumDuration: Duration = .seconds(3)

    private let isEnabled: @MainActor () -> Bool
    private var sessions: [UUID: Session] = [:]

    init(isEnabled: @escaping @MainActor () -> Bool) {
        self.isEnabled = isEnabled
    }

    func beginIfEnabled() async -> UUID? {
        guard AppRuntimeEnvironment.allowsNativeEffects, isEnabled(), #available(macOS 14.0, *), CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var captures: [(NSScreen, CGImage)] = []
            for screen in NSScreen.screens {
                guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let display = content.displays.first(where: { $0.displayID == displayNumber.uint32Value }) else {
                    return nil
                }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                // SCDisplay reports points; capture at the screen's pixel size so Retina frames stay sharp.
                configuration.width = Int((CGFloat(display.width) * screen.backingScaleFactor).rounded())
                configuration.height = Int((CGFloat(display.height) * screen.backingScaleFactor).rounded())
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                captures.append((screen, image))
            }
            guard !captures.isEmpty else { return nil }
            let windows = captures.map { screen, image -> NSWindow in
                let window = NSWindow(contentRect: screen.frame,
                                      styleMask: .borderless,
                                      backing: .buffered,
                                      defer: false)
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
                imageView.image = NSImage(cgImage: image, size: screen.frame.size)
                imageView.imageScaling = .scaleAxesIndependently
                imageView.imageAlignment = .alignCenter
                window.contentView = imageView
                window.backgroundColor = .black
                window.isOpaque = true
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                window.setFrame(screen.frame, display: false)
                return window
            }
            let sessionID = UUID()
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: ScreenCaptureDockSwitchFreezeProvider.maximumDuration) } catch { return }
                self?.end(sessionID)
            }
            sessions[sessionID] = Session(windows: windows, timeout: timeout)
            windows.forEach { $0.orderFrontRegardless() }
            await Task.yield()
            return sessionID
        } catch {
            return nil
        }
    }

    func end(_ sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        session.timeout?.cancel()
        session.windows.forEach { $0.orderOut(nil) }
    }
}
