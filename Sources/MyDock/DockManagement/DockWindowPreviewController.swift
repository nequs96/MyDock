import AppKit
import Combine
import QuartzCore
import SwiftUI

/// One hovered running app tile in the live Custom Dock, in screen coordinates.
struct WindowPreviewTarget {
    var key: String
    var item: DockItem
    var tileFrame: NSRect
    var dockFrame: NSRect
    var screenBounds: NSRect
    var position: DockPosition
    var colorScheme: ColorScheme
    var animationsEnabled: Bool
    weak var hostWindow: NSWindow?
}

/// What the preview panel shows. Updated only by `DockWindowPreviewController`.
@MainActor
final class DockWindowPreviewModel: ObservableObject {
    @Published var applicationName = ""
    @Published var applicationIcon: NSImage?
    @Published var position: DockPosition = .bottom
    @Published var colorScheme: ColorScheme = .light
    @Published var discovery: WindowPreviewDiscoveryState = .pending
    @Published var windows: [DockWindowDescriptor] = []
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var accessibilityTrusted = false
    @Published var screenRecordingAllowed = false
    @Published var captureSupported = false
    @Published var panelSize = CGSize(width: WindowPreviewPanelLayout.listWidth, height: 80)
    /// Changes on every fresh show so the appear effect replays; swaps keep it.
    @Published var appearanceID = UUID()

    var activate: @MainActor (DockWindowDescriptor) -> Void = { _ in }
    var close: @MainActor (DockWindowDescriptor) -> Void = { _ in }
    var showThumbnailsHelp: @MainActor () -> Void = {}
    var grantAccessibility: @MainActor () -> Void = {}

    var presentation: WindowPreviewPresentation {
        WindowPreviewPresentationPolicy.presentation(accessibilityTrusted: accessibilityTrusted,
                                                     screenRecordingAllowed: screenRecordingAllowed,
                                                     captureSupported: captureSupported,
                                                     discovery: discovery)
    }
}

/// Owns the hover preview panel: hover timing, window discovery, thumbnail capture and dismissal.
///
/// Nothing runs while idle: no timers, no polling and no event monitors. Discovery starts only
/// after the show delay, uses the existing bounded Accessibility deadline, and is cancelled with
/// any capture when the hover ends. Permission is never requested from a hover.
@MainActor
final class DockWindowPreviewController {
    static let shared = DockWindowPreviewController()

    var openSettings: (MyDockSettingsPage) -> Void = { _ in }
    private(set) var isEnabled = false

    private var machine = WindowPreviewHoverMachine()
    private var targets: [String: WindowPreviewTarget] = [:]
    private var currentTarget: WindowPreviewTarget?
    private let model = DockWindowPreviewModel()
    private var panel: NSPanel?
    private var isPanelVisible = false
    private var generation = UUID()
    private var deadlineTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var cache = WindowPreviewThumbnailCache<NSImage>()
    private var localMonitor: Any?

    /// The panel waits this long for discovery before showing a loading state.
    private static let revealFallback: Duration = .milliseconds(200)
    /// Windows captured this recently are shown from the cache, not captured again.
    private static let recaptureInterval: TimeInterval = 5
    private static let escapeKeyCode: UInt16 = 53

    private init() {
        model.activate = { [weak self] window in self?.activateWindow(window) }
        model.close = { [weak self] window in self?.closeWindow(window) }
        model.showThumbnailsHelp = { [weak self] in self?.openThumbnailPermissions() }
        model.grantAccessibility = { [weak self] in self?.requestAccessibility() }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Inputs

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard !enabled else { return }
        dismiss()
        machine = WindowPreviewHoverMachine()
        targets = [:]
        cache.removeAll()
        updateMonitors()
    }

    func pointerEnteredTile(_ target: WindowPreviewTarget) {
        guard isEnabled, AppRuntimeEnvironment.allowsNativeEffects else { return }
        targets[target.key] = target
        // Swaps reposition to the newly hovered tile.
        if machine.displayedTarget != nil { currentTarget = target }
        apply(machine.handle(.enterTile(target.key), at: now))
    }

    func pointerExitedTile(key: String) {
        apply(machine.handle(.exitTile(key), at: now))
    }

    func pointerInPanel(_ inside: Bool) {
        apply(machine.handle(inside ? .enterPanel : .exitPanel, at: now))
    }

    /// Escape, a click in the Dock, the Dock hiding, or the setting turning off.
    func dismiss() {
        apply(machine.handle(.dismiss, at: now))
    }

    // MARK: State machine effects

    private func apply(_ effect: WindowPreviewHoverMachine.Effect) {
        switch effect {
        case .noChange: break
        case .show(let key): present(key, swapping: false)
        case .swap(let key): present(key, swapping: true)
        case .close: closePanel()
        }
        let retained = machine.retainedTargets
        targets = targets.filter { retained.contains($0.key) }
        scheduleDeadline()
        updateMonitors()
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard let deadline = machine.nextDeadline else { return }
        let delay = max(0, deadline - now)
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.deadlineTask = nil
            self.apply(self.machine.handle(.tick, at: self.now))
        }
    }

    private func present(_ key: String, swapping: Bool) {
        guard let target = targets[key], target.hostWindow != nil else {
            _ = machine.handle(.dismiss, at: now)
            closePanel()
            return
        }
        cancelWork()
        let generation = UUID()
        self.generation = generation
        currentTarget = target

        model.applicationName = target.item.displayName
        model.applicationIcon = AppLauncher.icon(for: target.item, size: 32)
        model.position = target.position
        model.colorScheme = target.colorScheme
        model.windows = []
        model.thumbnails = [:]
        model.discovery = .pending
        if !swapping || !isPanelVisible { model.appearanceID = UUID() }

        let trusted = WindowAccessibilityService.isTrusted()
        model.accessibilityTrusted = trusted
        model.captureSupported = Self.captureSupported
        model.screenRecordingAllowed = Self.screenRecordingAllowed()

        guard trusted else {
            model.discovery = .permissionRequired
            layoutPanel()
            return
        }
        guard let identity = AppLauncher.runningIdentity(for: target.item) else {
            model.discovery = .unavailable
            layoutPanel()
            return
        }
        if isPanelVisible {
            // Keep the current frame, re-anchored, while the new app's windows load.
            layoutPanel()
        } else {
            revealTask = Task { [weak self] in
                do { try await Task.sleep(for: DockWindowPreviewController.revealFallback) } catch { return }
                guard let self, self.generation == generation, !self.isPanelVisible else { return }
                self.layoutPanel()
            }
        }
        startDiscovery(identity, generation: generation)
    }

    private func startDiscovery(_ identity: NativeApplicationIdentity, generation: UUID) {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            let signpost = PerformanceSignposts.begin("WindowPreviewDiscovery")
            let worker = Task.detached(priority: .userInitiated) { WindowAccessibilityService.discoverWindows(for: identity) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            PerformanceSignposts.end("WindowPreviewDiscovery", signpost)
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.applyDiscovery(result, generation: generation)
        }
    }

    private func applyDiscovery(_ result: WindowAccessibilityService.WindowDiscoveryResult, generation: UUID) {
        switch result {
        case .available(let windows):
            let displayed = WindowPreviewListPolicy.displayed(windows)
            let timestamp = now
            var thumbnails: [String: NSImage] = [:]
            for window in displayed {
                if let cached = cache.image(for: window.id, at: timestamp) {
                    thumbnails[window.id] = cached
                } else if window.isMinimized, let retained = WindowAccessibilityMonitor.shared.preview(for: window) {
                    // Minimized windows cannot be captured; reuse the opt-in minimized-window preview.
                    thumbnails[window.id] = retained
                }
            }
            model.windows = displayed
            model.thumbnails = thumbnails
            model.discovery = .windows(displayed.count)
        case .permissionRequired:
            model.accessibilityTrusted = false
            model.discovery = .permissionRequired
        case .applicationUnavailable, .unavailable:
            model.discovery = .unavailable
        }
        revealTask?.cancel()
        revealTask = nil
        layoutPanel()
        if model.presentation.body == .thumbnails {
            startCapture(model.windows, generation: generation)
        }
    }

    /// Captures run only while the panel is open, in the service's bounded batches.
    private func startCapture(_ windows: [DockWindowDescriptor], generation: UUID) {
        let visible = windows.filter { !$0.isMinimized }
        guard !visible.isEmpty, isPanelVisible else { return }
        let allIDs = Set(visible.map(\.id))
        let timestamp = now
        let recent = Set(allIDs.filter { cache.isFresh($0, within: Self.recaptureInterval, at: timestamp) })
        guard !recent.isSuperset(of: allIDs) else { return }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            var attempted = recent
            while !Task.isCancelled {
                let batch = await WindowPreviewCapturer.captureVisibleWindows(descriptors: visible, freshIDs: attempted)
                guard let controller = self, !Task.isCancelled, controller.generation == generation,
                      controller.isPanelVisible else { return }
                let storedAt = controller.now
                for (id, image) in batch.images where allIDs.contains(id) {
                    controller.cache.store(image, for: id, at: storedAt)
                    controller.model.thumbnails[id] = image
                }
                guard !batch.attemptedIDs.isEmpty else { return }
                attempted.formUnion(batch.attemptedIDs)
                if attempted.isSuperset(of: allIDs) { return }
            }
        }
    }

    private func cancelWork() {
        generation = UUID()
        discoveryTask?.cancel()
        discoveryTask = nil
        captureTask?.cancel()
        captureTask = nil
        revealTask?.cancel()
        revealTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Panel

    private func layoutPanel() {
        guard let target = currentTarget, let host = target.hostWindow, host.isVisible else {
            _ = machine.handle(.dismiss, at: now)
            closePanel()
            return
        }
        let presentation = model.presentation
        var size = WindowPreviewPanelLayout.size(for: presentation, windowCount: model.windows.count,
                                                 position: target.position)
        if presentation.body == .loading, isPanelVisible, let panel { size = panel.frame.size }
        let frame = WindowPreviewPanelGeometry.frame(size: size, tile: target.tileFrame, dock: target.dockFrame,
                                                     position: target.position, bounds: target.screenBounds)
        let panel = ensurePanel()
        model.panelSize = frame.size
        panel.setFrame(frame, display: true)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            // A child window keeps the auto-hidden Dock revealed while the pointer is over it.
            host.addChildWindow(panel, ordered: .above)
        }
        panel.level = host.level
        panel.invalidateShadow()
        guard !isPanelVisible else { return }
        isPanelVisible = true
        // A fade only: no scale or slide on the window, so Reduce Motion needs no other path.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = target.animationsEnabled ? 0.14 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        updateMonitors()
    }

    private func closePanel() {
        cancelWork()
        currentTarget = nil
        guard let panel else { return }
        guard isPanelVisible else {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            return
        }
        isPanelVisible = false
        let generation = self.generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AccessibilityDisplayState.shared.reduceMotion ? 0.08 : 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, !self.isPanelVisible, self.generation == generation else { return }
                // Detach so the reveal policy and profile swipes no longer see a child window.
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
        }
        updateMonitors()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: WindowPreviewPanelLayout.listWidth, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = WindowPreviewHostingView(rootView: WindowPreviewPanelView(model: model))
        hosting.onPointerInside = { [weak self] inside in self?.pointerInPanel(inside) }
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    // MARK: Actions

    private func activateWindow(_ window: DockWindowDescriptor) {
        // Restores a minimized window, raises it and activates its app (existing revalidated path).
        WindowAccessibilityService.activate(window)
        dismiss()
    }

    private func closeWindow(_ window: DockWindowDescriptor) {
        // A close request is not a closed window: the app may ask to save. Re-read the list.
        WindowAccessibilityService.close(window)
        guard let identity = window.applicationIdentity else { return }
        let generation = self.generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self, self.generation == generation, self.isPanelVisible else { return }
            self.startDiscovery(identity, generation: generation)
        }
    }

    private func openThumbnailPermissions() {
        dismiss()
        openSettings(.permissions)
    }

    private func requestAccessibility() {
        dismiss()
        // An explicit click: the system prompt lists MyDock under Accessibility.
        _ = WindowAccessibilityService.requestAccessPrompt()
    }

    // MARK: Event monitors (installed only while hovering or open)

    private func updateMonitors() {
        let active = machine.phase != .idle
        if active, localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleLocalEvent(event) }
                return event
            }
        } else if !active, let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        // No system-wide key monitor: moving the pointer away already closes the panel, and a
        // global key listener would observe typing in other apps.
    }

    private func handleLocalEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == Self.escapeKeyCode { dismiss() }
            return
        }
        // Clicks and scrolls inside the panel belong to it. Anywhere else (a tile click keeps its
        // normal action, a drag, a context menu, scrolling the Dock) closes the panel.
        if let panel, isPanelVisible, event.windowNumber == panel.windowNumber { return }
        dismiss()
    }

    // MARK: Permissions (observed, never requested here)

    private static var captureSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private static func screenRecordingAllowed() -> Bool {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return false }
        return CGPreflightScreenCaptureAccess()
    }
}

/// The panel's hosting view reports pointer enter/exit for the hover policy and accepts the
/// first click while MyDock is in the background, like the Dock panel.
final class WindowPreviewHostingView: NSHostingView<WindowPreviewPanelView> {
    var onPointerInside: (@MainActor (Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === pointerTrackingArea { onPointerInside?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === pointerTrackingArea { onPointerInside?(false) }
    }
}

/// A hit-test-transparent region behind a running app tile. It reports pointer enter/exit with
/// the tile's screen frame; clicks, drags and context menus reach the tile unchanged.
struct DockWindowPreviewHoverRegion: NSViewRepresentable {
    var key: String
    var item: DockItem
    var position: DockPosition
    var colorScheme: ColorScheme
    var animationsEnabled: Bool

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView()
        update(view)
        return view
    }

    func updateNSView(_ view: RegionView, context: Context) {
        update(view)
    }

    private func update(_ view: RegionView) {
        if view.key != key { view.endHover() }
        view.key = key
        view.item = item
        view.position = position
        view.colorScheme = colorScheme
        view.animationsEnabled = animationsEnabled
    }

    final class RegionView: NSView {
        var key = ""
        var item: DockItem?
        var position: DockPosition = .bottom
        var colorScheme: ColorScheme = .light
        var animationsEnabled = true
        private var regionTrackingArea: NSTrackingArea?
        private var isInside = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let regionTrackingArea { removeTrackingArea(regionTrackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            regionTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            guard event.trackingArea === regionTrackingArea, let item, let window else { return }
            let screen = window.screen ?? NSScreen.main
            let screenFrame = screen?.frame ?? window.frame
            let usableTop = screen?.visibleFrame.maxY ?? screenFrame.maxY
            let screenBounds = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width,
                                      height: max(0, usableTop - screenFrame.minY))
            isInside = true
            DockWindowPreviewController.shared.pointerEnteredTile(WindowPreviewTarget(
                key: key, item: item, tileFrame: window.convertToScreen(convert(bounds, to: nil)),
                dockFrame: window.frame, screenBounds: screenBounds, position: position, colorScheme: colorScheme,
                animationsEnabled: animationsEnabled, hostWindow: window))
        }

        override func mouseExited(with event: NSEvent) {
            guard event.trackingArea === regionTrackingArea else { return }
            endHover()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { endHover() }
        }

        func endHover() {
            guard isInside else { return }
            isInside = false
            DockWindowPreviewController.shared.pointerExitedTile(key: key)
        }
    }
}
