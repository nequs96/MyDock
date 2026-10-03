import AppKit
import QuartzCore
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The borderless panel must never expose the rectangular backing of a
/// material/effect layer. Apply the same outline at the native hosting boundary.
final class DockSurfaceHostingView<Content: View>: NSHostingView<Content> {
    var surfaceCornerRadius: CGFloat = 0 { didSet { updateSurfaceMask() } }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        updateSurfaceMask()
    }

    private func updateSurfaceMask() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = surfaceCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.shadowOpacity = 0
    }
}


@MainActor
final class CustomDockWindowController {
    static let animationPreviewNotification = Notification.Name("MyDockPreviewDockAnimation")
    private var animationPreviewTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var observation: AnyCancellable?
    private var screenObservation: AnyCancellable?
    private var runtimeObservations: [AnyCancellable] = []
    private var menuObservations: [AnyCancellable] = []
    private var menuTrackingDepth = 0
    private var presentationVisible = false
    private var lastPresentation: DockPresentationSignature?
    private var transitionGeneration = UUID()
    private var transitionInFlight: DockTransitionPolicy.Snapshot?
    private var applicationObservation: AnyCancellable?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var profileGestureMonitor: Any?
    private var revealPanel: NSPanel?
    private var expandedFrame = NSRect.zero
    private var revealFrame = NSRect.zero
    private var currentPosition: DockPosition = .bottom
    private var currentColor: DockProfileColor = .blue
    private var perpendicularSwipeDelta: CGFloat = 0
    private var parallelSwipeDelta: CGFloat = 0
    private var commandScrollDelta: CGFloat = 0
    private var presentationTask: Task<Void, Never>?
    private var pendingRevealTask: Task<Void, Never>?
    private var usingDisplayFallback = false
    private var noScreenAvailable = false
    private let store: ProfileStore
    private let openSettings: (MyDockSettingsPage) -> Void
    private let overviewIsPresent: (NSRect, [NSRect]) -> Bool

    init(store: ProfileStore, openSettings: @escaping (MyDockSettingsPage) -> Void = { _ in },
         overviewIsPresent: @escaping (NSRect, [NSRect]) -> Bool = { SystemOverviewPolicy.isPresent(screen: $0, dockFrames: $1) }) {
        self.store = store
        self.openSettings = openSettings
        self.overviewIsPresent = overviewIsPresent
        menuObservations = [
            NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingDepth += 1 }
            },
            NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingDepth = max(0, (self?.menuTrackingDepth ?? 0) - 1) }
            }
        ]
        _ = store.widgetLifecycle
        observation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.update(state: state)
        }
        runtimeObservations.append(store.$dockResizePreview.dropFirst()
            .throttle(for: .milliseconds(8), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, let profile = self.store.activeCustomProfile,
                      let screen = self.screen(for: self.store.state.settings) else { return }
                self.expandedFrame = self.place(panel, on: screen, profile: profile,
                    settings: self.store.effectiveSettings(for: profile), animate: false)
            })
        screenObservation = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.update(state: self.store.state)
            }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        applicationObservation = Publishers.Merge(
            workspaceNotifications.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspaceNotifications.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.update(state: self.store.state)
        }
        runtimeObservations += [
            NotificationCenter.default.publisher(for: Self.animationPreviewNotification).sink { [weak self] notification in
                guard let self, let sender = notification.object as? ProfileStore, sender === self.store else { return }
                self.animationPreviewTask?.cancel()
                self.animationPreviewTask = Task { @MainActor [weak self] in
                    guard let self, self.canPresentDock else { return }
                    self.presentDock(visible: false)
                    do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                    self.presentDock(visible: true)
                }
            },
            WindowAccessibilityMonitor.shared.$windows.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in guard let self else { return }; self.update(state: self.store.state) }
            },
            NowPlayingMonitor.shared.$runningSources.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in guard let self else { return }; self.update(state: self.store.state) }
            }
        ]
    }

    func update(state: PersistentState) {
        WindowAccessibilityMonitor.shared.setPreviewCacheRetentionEnabled(
            state.settings.showMinimizedWindows && state.settings.showWindowPreviews
        )
        DockBadgeMonitor.shared.setEnabled(state.settings.showAppBadges)
        guard state.settings.setupMode != .nativeOnly,
              let profileID = state.settings.activeCustomProfileID,
              let profile = state.profiles.first(where: { $0.id == profileID && $0.kind == .custom }) else {
            usingDisplayFallback = false
            noScreenAvailable = false
            SystemActivityMonitor.shared.setDockVisible(false)
            NetworkActivityMonitor.shared.setDockVisible(false)
            NowPlayingMonitor.shared.setDockVisible(false)
            RefreshScheduler.shared.setDockVisible(false)
            store.widgetData.setVisible(false)
            DockBadgeMonitor.shared.setDockVisible(false)
            WindowAccessibilityMonitor.shared.setEnabled(false)
            lastPresentation = nil
            presentationVisible = false
            panel?.alphaValue = 0
            panel?.orderOut(nil)
            revealPanel?.orderOut(nil)
            presentationTask?.cancel(); presentationTask = nil
            stopMouseMonitoring()
            stopProfileGestureMonitoring()
            return
        }
        guard let screen = screen(for: state.settings) else {
            SystemActivityMonitor.shared.setDockVisible(false)
            NetworkActivityMonitor.shared.setDockVisible(false)
            NowPlayingMonitor.shared.setDockVisible(false)
            RefreshScheduler.shared.setDockVisible(false)
            store.widgetData.setVisible(false)
            DockBadgeMonitor.shared.setDockVisible(false)
            WindowAccessibilityMonitor.shared.setEnabled(false)
            lastPresentation = nil
            presentationVisible = false
            panel?.alphaValue = 0
            panel?.orderOut(nil)
            revealPanel?.orderOut(nil)
            presentationTask?.cancel(); presentationTask = nil
            stopMouseMonitoring()
            stopProfileGestureMonitoring()
            return
        }
        // The preview subscriber owns frame changes during a drag. Replacing
        // rootView here can interrupt the gesture and restart live monitors.
        if DockInteractionState.isResizing, lastPresentation?.profileID == profile.id { return }
        let resolvedSettings = store.effectiveSettings(for: profile)
        let layout = DockRenderModel(profile: profile, settings: resolvedSettings,
            runningApplications: RuntimeDockApplications.items(), windows: WindowAccessibilityMonitor.shared.windows,
            runningMediaSources: NowPlayingMonitor.shared.runningSources,
            pinnedApplicationURLs: RuntimeDockApplications.pinnedURLs(in: profile))
        let signature = DockPresentationSignature(profileID: profile.id, color: profile.color, settings: DockPresentationSettings(resolvedSettings), global: DockPresentationSettings(state.settings),
            displayFrame: screen.visibleFrame, entries: layout.entries.map { "\($0.id):\($0.length(settings: resolvedSettings, scale: 1))" })
        reconcileTransition(settings: state.settings)
        guard signature != lastPresentation else { return }
        let resizing = lastPresentation?.settings.size != resolvedSettings.customDockSize
        lastPresentation = signature
        currentPosition = resolvedSettings.customDockPosition
        currentColor = DockProfileColor(rawValue: profile.color) ?? .blue
        let root = CustomDockView(store: store, profile: profile, openSettings: openSettings)
        if let panel, let hosting = panel.contentView as? DockSurfaceHostingView<CustomDockView> {
            PerformanceSignposts.measure("DockRootAssignment") { hosting.rootView = root }
#if DEBUG
            PerformanceSignposts.noteRootAssignment()
#endif
            hosting.surfaceCornerRadius = CGFloat(resolvedSettings.customDockCornerRadius)
            expandedFrame = place(panel, on: screen, profile: profile, settings: resolvedSettings, animate: !resizing)
        } else {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 84),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.alphaValue = 0
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let hosting = DockSurfaceHostingView(rootView: root)
            hosting.surfaceCornerRadius = CGFloat(resolvedSettings.customDockCornerRadius)
            panel.contentView = hosting
            self.panel = panel
            expandedFrame = place(panel, on: screen, profile: profile, settings: resolvedSettings)
        }
        startPresentationMonitoring()
        updateRevealPanel(on: screen, shouldShowHandle: state.settings.showRevealHandle)
        configureWindowMode(desktop: state.settings.customDockDesktopMode)
        startProfileGestureMonitoring()
        if (state.settings.automaticallyHideCustomDock && !state.settings.customDockDesktopMode)
            || state.settings.hideCustomDockWhenSystemDockAppears {
            startMouseMonitoring()
            updateAutoHide(mouseLocation: NSEvent.mouseLocation)
        } else {
            stopMouseMonitoring()
            revealPanel?.orderOut(nil)
            presentDock(visible: true)
            SystemActivityMonitor.shared.setDockVisible(true)
            NetworkActivityMonitor.shared.setDockVisible(true)
            NowPlayingMonitor.shared.setDockVisible(true)
            RefreshScheduler.shared.setDockVisible(true)
            store.widgetData.setVisible(true)
            DockBadgeMonitor.shared.setDockVisible(true)
            configureWindowMonitoring(state.settings)
        }
    }

    private func screen(for settings: AppSettings) -> NSScreen? {
        let selectedScreen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == settings.customDockDisplayID
        }
        let fallback = selectedScreen == nil && settings.customDockDisplayID != nil
        if fallback && !usingDisplayFallback {
            DiagnosticsService.shared.record(.customDockDisplayFallback)
        } else if !fallback && usingDisplayFallback {
            DiagnosticsService.shared.record(.customDockDisplayRestored)
        }
        usingDisplayFallback = fallback
        let screen = selectedScreen ?? NSScreen.main ?? NSScreen.screens.first
        if screen == nil && !noScreenAvailable {
            DiagnosticsService.shared.record(.customDockScreenUnavailable)
        }
        noScreenAvailable = screen == nil
        return screen
    }

    private func dockPlacementFrame(on screen: NSScreen) -> NSRect {
        // Keep the menu bar safe area, but reclaim the space occupied by Apple's Dock.
        DockSurfaceMetrics.placementArea(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                         mode: store.state.settings.setupMode)
    }

    private func place(_ panel: NSPanel, on screen: NSScreen, profile: DockProfile, settings: AppSettings, animate: Bool = false) -> NSRect {
        let visible = dockPlacementFrame(on: screen)
        let scale = CGFloat(min(max(settings.customDockSize, 0.65), 1.5))
        let tileLength = (54 + (settings.magnificationEnabled ? 22 : 0)) * scale
        let model = DockRenderModel(profile: profile, settings: settings, runningApplications: RuntimeDockApplications.items(),
                                    windows: WindowAccessibilityMonitor.shared.windows,
                                    runningMediaSources: NowPlayingMonitor.shared.runningSources,
                                    pinnedApplicationURLs: RuntimeDockApplications.pinnedURLs(in: profile))
        let itemLength = model.contentLength(settings: settings, scale: scale) + (settings.magnificationEnabled ? 32 : 22) * scale
        let maxLength = settings.customDockPosition == .bottom ? visible.width - 40 : visible.height - 60
        let length = min(max(itemLength, 100), max(maxLength, 100))
        let frame: NSRect
        switch settings.customDockPosition {
        case .bottom:
            let width = length
            let height = tileLength + 22 * scale
            frame = NSRect(x: visible.midX - width / 2, y: visible.minY + 10, width: width, height: height)
        case .left:
            let width = tileLength + 22 * scale
            let height = length
            frame = NSRect(x: visible.minX + 10, y: visible.midY - height / 2, width: width, height: height)
        case .right:
            let width = tileLength + 22 * scale
            let height = length
            frame = NSRect(x: visible.maxX - width - 10, y: visible.midY - height / 2, width: width, height: height)
        }
        panel.setFrame(frame, display: true, animate: animate && presentationVisible && settings.dockAnimationsEnabled && !AccessibilityDisplayState.shared.reduceMotion)
        return frame
    }

    private func updateRevealPanel(on screen: NSScreen, shouldShowHandle: Bool) {
        let handleSize: CGFloat = 6
        let handleLength: CGFloat = 38
        let visible = dockPlacementFrame(on: screen)
        switch currentPosition {
        case .bottom:
            revealFrame = NSRect(x: visible.midX - handleLength / 2, y: visible.minY + 1, width: handleLength, height: handleSize)
        case .left:
            revealFrame = NSRect(x: visible.minX + 1, y: visible.midY - handleLength / 2, width: handleSize, height: handleLength)
        case .right:
            revealFrame = NSRect(x: visible.maxX - handleSize - 1, y: visible.midY - handleLength / 2, width: handleSize, height: handleLength)
        }

        let content = RevealHandleView(position: currentPosition,
                                       color: color(for: currentColor),
                                       isVisible: shouldShowHandle)
        if let revealPanel {
            revealPanel.contentView = NSHostingView(rootView: content)
            revealPanel.setFrame(revealFrame, display: true, animate: false)
        } else {
            let handle = NSPanel(contentRect: revealFrame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            handle.isFloatingPanel = true
            handle.level = .floating
            handle.backgroundColor = .clear
            handle.isOpaque = false
            handle.hasShadow = false
            handle.hidesOnDeactivate = false
            handle.acceptsMouseMovedEvents = true
            handle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            handle.contentView = NSHostingView(rootView: content)
            revealPanel = handle
        }
    }

    private func configureWindowMode(desktop: Bool) {
        let level = desktop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))) : .floating
        let behavior: NSWindow.CollectionBehavior = desktop
            ? [.canJoinAllSpaces, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel?.isFloatingPanel = !desktop
        panel?.level = level
        panel?.collectionBehavior = behavior
        revealPanel?.isFloatingPanel = !desktop
        revealPanel?.level = level
        revealPanel?.collectionBehavior = behavior
    }

    private func startPresentationMonitoring() {
        guard presentationTask == nil else { return }
        presentationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                updateAutoHide(mouseLocation: NSEvent.mouseLocation)
            }
        }
    }

    private func startMouseMonitoring() {
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged]
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateAutoHide(mouseLocation: NSEvent.mouseLocation)
                }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.updateAutoHide(mouseLocation: NSEvent.mouseLocation)
                }
                return event
            }
        }
    }

    private func stopMouseMonitoring() {
        pendingRevealTask?.cancel()
        pendingRevealTask = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        mouseMonitor = nil
        localMouseMonitor = nil
    }

    private func startProfileGestureMonitoring() {
        guard profileGestureMonitor == nil else { return }
        profileGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleProfileGesture(event) }
            return event
        }
    }

    private func stopProfileGestureMonitoring() {
        if let profileGestureMonitor { NSEvent.removeMonitor(profileGestureMonitor) }
        profileGestureMonitor = nil
        perpendicularSwipeDelta = 0
        parallelSwipeDelta = 0
        commandScrollDelta = 0
    }

    private func handleProfileGesture(_ event: NSEvent) {
        guard let panel,
              event.window === panel else { return }
        guard panel.childWindows?.isEmpty ?? true else { return }

        let isHorizontal = currentPosition == .bottom
        let perpendicularDelta = isHorizontal ? event.scrollingDeltaY : event.scrollingDeltaX
        let parallelDelta = isHorizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            commandScrollDelta = 0
            perpendicularSwipeDelta = 0
            parallelSwipeDelta = 0
        }

        if event.modifierFlags.contains(.command) {
            if event.phase.contains(.cancelled) {
                commandScrollDelta = 0
                return
            }
            if event.hasPreciseScrollingDeltas {
                if event.phase.contains(.changed) { commandScrollDelta += perpendicularDelta }
                guard event.phase.contains(.ended) else { return }
                activateCustomProfile(forPerpendicularDelta: commandScrollDelta + perpendicularDelta)
            } else {
                activateCustomProfile(forPerpendicularDelta: perpendicularDelta * 48)
            }
            commandScrollDelta = 0
            return
        }

        guard event.hasPreciseScrollingDeltas else { return }
        if event.phase.contains(.changed) {
            perpendicularSwipeDelta += perpendicularDelta
            parallelSwipeDelta += parallelDelta
        }
        if event.phase.contains(.cancelled) {
            perpendicularSwipeDelta = 0
            parallelSwipeDelta = 0
            return
        }
        guard event.phase.contains(.ended) else { return }

        activateCustomProfile(forPerpendicularDelta: perpendicularSwipeDelta + perpendicularDelta,
                              parallelDelta: parallelSwipeDelta + parallelDelta)
        perpendicularSwipeDelta = 0
        parallelSwipeDelta = 0
    }

    private func activateCustomProfile(forPerpendicularDelta perpendicularDelta: CGFloat,
                                       parallelDelta: CGFloat = 0) {
        guard let currentIndex = store.customProfiles.firstIndex(where: { $0.id == store.state.settings.activeCustomProfileID }),
              let destination = DockProfileSwipePolicy.destinationIndex(currentIndex: currentIndex,
                                                                         perpendicularDelta: perpendicularDelta,
                                                                         parallelDelta: parallelDelta,
                                                                         profileCount: store.customProfiles.count) else { return }
        store.activate(store.customProfiles[destination].id)
    }

    private func updateAutoHide(mouseLocation: NSPoint) {
        // Mouse events can already be queued when changing modes or removing a profile.
        guard canPresentDock, let panel else { return }
        // Menus are separate AppKit windows, so their submenus are outside the Dock's hover frame.
        // Keep the anchor alive for the entire tracking session, including spacer submenus.
        if menuTrackingDepth > 0 || DockInteractionState.isResizing {
            pendingRevealTask?.cancel(); pendingRevealTask = nil
            showDockPanel()
            return
        }
        let dockFrames = SystemDockVisibilityReader.visibleDockFrames()
        if let screen = screen(for: store.state.settings), overviewIsPresent(screen.frame, dockFrames) {
            pendingRevealTask?.cancel(); pendingRevealTask = nil
            hideDockPanelForSystemDock()
            return
        }
        if store.state.settings.hideCustomDockWhenSystemDockAppears,
           SystemDockVisibilityReader.isVisible(overlapping: expandedFrame) {
            pendingRevealTask?.cancel()
            pendingRevealTask = nil
            hideDockPanelForSystemDock()
            return
        }
        if store.state.settings.customDockDesktopMode {
            pendingRevealTask?.cancel()
            pendingRevealTask = nil
            showDockPanel()
            return
        }
        guard store.state.settings.automaticallyHideCustomDock else {
            pendingRevealTask?.cancel()
            pendingRevealTask = nil
            showDockPanel()
            return
        }
        let popoutFrames = (panel.childWindows ?? []).map(\.frame)
        if presentationVisible && CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: mouseLocation,
                                                               expandedFrame: expandedFrame,
                                                               popoutFrames: popoutFrames) {
            pendingRevealTask?.cancel()
            pendingRevealTask = nil
            showDockPanel()
        } else if CustomDockVisibilityPolicy.isAtRevealEdge(mouseLocation: mouseLocation, revealFrame: revealFrame) {
            scheduleDwellReveal()
            hideDockPanel()
        } else {
            pendingRevealTask?.cancel()
            pendingRevealTask = nil
            hideDockPanel()
        }
    }

    private func scheduleDwellReveal() {
        guard canPresentDock, pendingRevealTask == nil else { return }
        pendingRevealTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, self.canPresentDock else { return }
            self.pendingRevealTask = nil
            if self.store.state.settings.hideCustomDockWhenSystemDockAppears,
               SystemDockVisibilityReader.isVisible(overlapping: self.expandedFrame) {
                self.hideDockPanelForSystemDock()
                return
            }
            let mouseLocation = NSEvent.mouseLocation
            let popoutFrames = (self.panel?.childWindows ?? []).map(\.frame)
            if CustomDockVisibilityPolicy.shouldReveal(mouseLocation: mouseLocation,
                                                       expandedFrame: self.expandedFrame,
                                                       revealFrame: self.revealFrame,
                                                       popoutFrames: popoutFrames) {
                self.showDockPanel()
            }
        }
    }

    private func showDockPanel() {
        guard canPresentDock else { return }
        if panel?.isVisible == false { DiagnosticsService.shared.record(.customDockShown) }
        revealPanel?.orderOut(nil)
        presentDock(visible: true)
        SystemActivityMonitor.shared.setDockVisible(true)
        NetworkActivityMonitor.shared.setDockVisible(true)
        NowPlayingMonitor.shared.setDockVisible(true)
        RefreshScheduler.shared.setDockVisible(true)
        store.widgetData.setVisible(true)
        DockBadgeMonitor.shared.setDockVisible(true)
        configureWindowMonitoring(store.state.settings)
    }

    private var canPresentDock: Bool {
        CustomDockVisibilityPolicy.canPresent(mode: store.state.settings.setupMode,
                                             hasActiveProfile: store.activeCustomProfile != nil)
    }

    private func configureWindowMonitoring(_ settings: AppSettings) {
        WindowAccessibilityMonitor.shared.setEnabled(
            settings.showMinimizedWindows || settings.clickFocusedAppToMinimize,
            previewsEnabled: settings.showMinimizedWindows && settings.showWindowPreviews
        )
    }

    private func hideDockPanel() {
        if panel?.isVisible == true { DiagnosticsService.shared.record(.customDockHidden) }
        presentDock(visible: false)
        revealPanel?.orderFrontRegardless()
        SystemActivityMonitor.shared.setDockVisible(false)
        NetworkActivityMonitor.shared.setDockVisible(false)
        NowPlayingMonitor.shared.setDockVisible(false)
        RefreshScheduler.shared.setDockVisible(false)
        store.widgetData.setVisible(false)
        DockBadgeMonitor.shared.setDockVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
    }

    private func hideDockPanelForSystemDock() {
        if panel?.isVisible == true { DiagnosticsService.shared.record(.customDockHidden) }
        presentDock(visible: false)
        revealPanel?.orderOut(nil)
        SystemActivityMonitor.shared.setDockVisible(false)
        NetworkActivityMonitor.shared.setDockVisible(false)
        NowPlayingMonitor.shared.setDockVisible(false)
        RefreshScheduler.shared.setDockVisible(false)
        store.widgetData.setVisible(false)
        DockBadgeMonitor.shared.setDockVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
    }

    /// H4: a style or Off/Reduce Motion change while a reveal/hide transition is running must not leave
    /// alpha, offset or scale at an intermediate value. Normalizes straight to the final state.
    private func reconcileTransition(settings: AppSettings) {
        guard let panel, let inFlight = transitionInFlight else { return }
        let reduceMotion = AccessibilityDisplayState.shared.reduceMotion || !settings.dockAnimationsEnabled
        let now = DockTransitionPolicy.Snapshot(visible: presentationVisible, style: settings.dockAnimationStyle, reduceMotion: reduceMotion)
        guard DockTransitionPolicy.action(inFlight: inFlight, requested: now) == .normalizeImmediately else { return }
        PerformanceSignposts.event("DockTransitionNormalized")
        transitionGeneration = UUID()
        transitionInFlight = nil
        let final = DockTransitionPolicy.finalState(now)
        if let layer = panel.contentView?.layer {
            layer.removeAnimation(forKey: "dockPresentationScale")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeScale(final.scale, final.scale, 1)
            CATransaction.commit()
        }
        // Setting the property directly under a zero-duration group cancels the running animator animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.animator().alphaValue = final.alpha
        }
        panel.alphaValue = final.alpha
        panel.setFrame(final.usesHiddenOffset
            ? DockPanelMotion.transitionFrame(from: expandedFrame, position: currentPosition, style: settings.dockAnimationStyle)
            : expandedFrame, display: true)
        if !now.visible { panel.orderOut(nil) }
    }

    private func presentDock(visible: Bool) {
        guard !visible || canPresentDock, let panel else { return }
        guard presentationVisible != visible else {
            reconcileTransition(settings: store.state.settings)
            return
        }
        presentationVisible = visible
        let generation = UUID()
        transitionGeneration = generation
        let settings = store.state.settings
        let reduceMotion = AccessibilityDisplayState.shared.reduceMotion || !settings.dockAnimationsEnabled
        transitionInFlight = DockTransitionPolicy.Snapshot(visible: visible, style: settings.dockAnimationStyle, reduceMotion: reduceMotion)
        let signpost = PerformanceSignposts.begin("DockPresentationTransition")
        let hiddenFrame = DockPanelMotion.transitionFrame(from: expandedFrame, position: currentPosition, style: settings.dockAnimationStyle)
        let wasVisible = panel.isVisible
        if visible {
            if reduceMotion || settings.dockAnimationStyle == .fade { panel.setFrame(expandedFrame, display: false) }
            else if !panel.isVisible { panel.setFrame(hiddenFrame, display: false) }
            panel.orderFrontRegardless()
        }
        if let layer = panel.contentView?.layer {
            // Grow the composited surface, not the window frame: changing its
            // viewport mid-animation would reflow overflow controls and tiles.
            let start = layer.presentation()?.transform.m11 ?? layer.transform.m11
            layer.removeAnimation(forKey: "dockPresentationScale")
            let target = reduceMotion ? CGFloat(1) : DockPanelMotion.scale(visible: visible, style: settings.dockAnimationStyle)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeScale(target, target, 1)
            CATransaction.commit()
            if !reduceMotion, settings.dockAnimationStyle == .grow {
                let animation = CABasicAnimation(keyPath: "transform.scale")
                animation.fromValue = visible && !wasVisible ? 0.94 : start
                animation.toValue = target
                animation.duration = DockPanelMotion.duration(visible: visible, enabled: true, reduceMotion: false)
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: "dockPresentationScale")
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DockPanelMotion.duration(visible: visible, enabled: settings.dockAnimationsEnabled, reduceMotion: AccessibilityDisplayState.shared.reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = visible ? 1 : 0
            if !reduceMotion { panel.animator().setFrame(visible ? expandedFrame : hiddenFrame, display: true) }
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                PerformanceSignposts.end("DockPresentationTransition", signpost)
                guard let self, self.transitionGeneration == generation else { return }
                self.transitionInFlight = nil
                guard !visible else { return }
                panel?.orderOut(nil)
            }
        }
    }

    private func color(for profileColor: DockProfileColor) -> Color {
        switch profileColor {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }
}

/// The running-process scan is deferred to this view's body, which SwiftUI evaluates when the
/// context menu opens rather than during every tile body pass. The captured identity is the
/// one observed at that moment and is revalidated again by each action.
private struct RunningApplicationMenuSection: View {
    let item: DockItem
    var body: some View {
        if let identity = AppLauncher.runningIdentity(for: item) {
            Button("Windows…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .activate) }
            Button("Close Window…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .close) }
            Divider()
            Button("Quit \(item.displayName)") { AppLauncher.quit(identity) }
        }
    }
}


private struct DockResizeCursor: NSViewRepresentable {
    var horizontal: Bool
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = horizontal ? .resizeUpDown : .resizeLeftRight
        view.window?.invalidateCursorRects(for: view)
    }
    final class CursorView: NSView {
        var cursor = NSCursor.resizeUpDown
        override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}


private struct RevealHandleView: View {
    var position: DockPosition
    var color: Color
    var isVisible: Bool
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    var body: some View {
        Group {
            if isVisible {
                Capsule()
                    .fill(accessibility.reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Capsule().fill(color.opacity(accessibility.reduceTransparency ? 1 : 0.65)))
                    .padding(position == .bottom ? .horizontal : .vertical, 4)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { if DockInteractionState.isResizing { $0.animation = nil } }
        .background(Color.clear)
    }
}

struct CustomDockView: View {
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: ProfileStore
    private var sourceProfile: DockProfile
    var profile: DockProfile {
        isPreview ? sourceProfile : store.state.profiles.first(where: { $0.id == sourceProfile.id }) ?? sourceProfile
    }
    var isPreview = false
    var usesLivePreviewData = false

    init(store: ProfileStore, profile: DockProfile, isPreview: Bool = false, usesLivePreviewData: Bool = false,
         openSettings: @escaping (MyDockSettingsPage) -> Void = { _ in }) {
        self.store = store
        sourceProfile = profile
        self.isPreview = isPreview
        self.usesLivePreviewData = usesLivePreviewData
        self.openSettings = openSettings
    }
    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    var openSettings: (MyDockSettingsPage) -> Void = { _ in }
    @Namespace private var profileTransformation
    @State private var popouts = DockPopoutSelection()
    private var systemTrashItem: DockItem { DockRenderModel.systemTrash }
    @State private var hoverPosition: CGFloat?
    @State private var runtimeApplications: [DockItem] = []
    @State private var hoveredItemID: UUID?
    @State private var longPressTriggeredItemID: UUID?
    @State private var resizeStartSize: CGFloat?
    @State private var resizeStartPointer: NSPoint?
    @State private var resizeDidChange = false
    @State private var resizeGripHovered = false
    @State private var linkIconMessage: String?
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared
    @ObservedObject private var windowMonitor = WindowAccessibilityMonitor.shared
    @ObservedObject private var nowPlayingMonitor = NowPlayingMonitor.shared
    @ObservedObject private var dockBadgeMonitor = DockBadgeMonitor.shared

    private var popoutMaxHeight: CGFloat {
        let selectedDisplayID = settings.customDockDisplayID
        let screen = NSScreen.screens.first { screen in
            guard let selectedDisplayID,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == selectedDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
        let visibleHeight = screen?.visibleFrame.height ?? 720
        return min(600, max(180, visibleHeight - 160))
    }

    @ViewBuilder private var switchProfileMenu: some View {
        Menu("Switch Profile") {
            if !store.nativeProfiles.isEmpty {
                Menu("macOS Dock") {
                    ForEach(store.nativeProfiles) { candidate in
                        profileMenuButton(candidate, isActive: settings.activeNativeProfileID == candidate.id)
                    }
                }
            }
            if !store.customProfiles.isEmpty {
                Menu("Custom Dock") {
                    ForEach(store.customProfiles) { candidate in
                        profileMenuButton(candidate, isActive: settings.activeCustomProfileID == candidate.id)
                    }
                }
            }
        }
    }

    private var addToDockMenu: some View {
        Menu("Add to Custom Dock") {
            Button("Application…", systemImage: "app.badge.plus", action: chooseApplication)
            Button("File…", systemImage: "doc.badge.plus", action: chooseFile)
            Button("Folder…", systemImage: "folder.badge.plus", action: chooseFolder)
            Button("Web Link…", systemImage: "link", action: addWebLink)
            Menu("Widget") {
                ForEach(WidgetCategory.allCases, id: \.rawValue) { category in
                    Menu(category.rawValue) {
                        ForEach(WidgetRegistry.all.filter { $0.category == category }) { definition in
                            Button(definition.name, systemImage: definition.symbol) {
                                store.add(.widget(definition.name), to: profile.id)
                            }
                        }
                    }
                }
            }
            Divider()
            ForEach(SpacerKind.allCases) { kind in
                Button("Add \(kind.title)") { store.add(.spacer(kind), to: profile.id) }
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add Application to Custom Dock"
        panel.prompt = "Add Application"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.add(.application(at: url), to: profile.id)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Folder to Custom Dock"
        panel.prompt = "Add Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.add(.file(at: url, isFolder: true), to: profile.id)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Add File to Custom Dock"
        panel.prompt = "Add File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.add(.file(at: url), to: profile.id)
    }

    private func addWebLink() {
        let alert = NSAlert()
        alert.messageText = "Add a Web Link"
        alert.informativeText = "Enter an HTTP or HTTPS address."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = DockLinkPolicy.validatedURL(field.stringValue) else {
            let error = NSAlert()
            error.messageText = "Enter a valid web address"
            error.informativeText = "MyDock accepts HTTP and HTTPS links only."
            error.runModal()
            return
        }
        store.add(.link(url, title: ""), to: profile.id)
    }

    private func renameLink(_ item: DockItem) {
        let alert = NSAlert()
        alert.messageText = "Rename Link"
        alert.informativeText = "Choose a name shown in this Dock. Clear the field to use the site's host name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = item.title
        field.placeholderString = item.url?.host
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Name")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = item.url?.host ?? item.url?.absoluteString ?? item.title
        store.updateItem(item.id, in: profile.id) { $0.title = title.isEmpty ? fallback : String(title.prefix(120)) }
    }

    private func changeLinkAddress(_ item: DockItem) {
        let alert = NSAlert()
        alert.messageText = "Change Link Address"
        alert.informativeText = "Use a valid HTTP or HTTPS address."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = item.url?.absoluteString ?? "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Address")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = DockLinkPolicy.validatedURL(field.stringValue) else {
            let error = NSAlert()
            error.messageText = "Enter a valid web address"
            error.informativeText = "MyDock accepts HTTP and HTTPS links only."
            error.runModal()
            return
        }
        let previousHost = item.url?.host?.lowercased()
        let previousDefaultTitle = item.url?.host
        store.updateItem(item.id, in: profile.id) { current in
            current.url = url
            if current.title == previousDefaultTitle, let newHost = url.host { current.title = newHost }
            if previousHost != url.host?.lowercased() { current.linkFaviconData = nil }
        }
    }

    private func fetchLinkIcon(_ item: DockItem) {
        guard let destination = item.url else { return }
        Task { @MainActor in
            let data = await SiteFaviconFetcher.fetchIconData(for: destination)
            guard let currentItem = store.state.profiles.first(where: { $0.id == profile.id })?.items.first(where: { $0.id == item.id }),
                  currentItem.url == destination else {
                linkIconMessage = "The link changed while MyDock was fetching its icon. Try again."
                return
            }
            guard let data else {
                linkIconMessage = "No safe HTTPS site icon was available for this link."
                return
            }
            store.updateItem(item.id, in: profile.id) { current in
                current.linkIcon = nil
                current.linkFaviconData = data
            }
            linkIconMessage = "The site icon was saved locally."
        }
    }

    private func profileMenuButton(_ candidate: DockProfile, isActive: Bool) -> some View {
        Button {
            activateProfileFromContextMenu(candidate)
        } label: {
            if isActive { Label(candidate.name, systemImage: "checkmark") }
            else { Text(candidate.name) }
        }
    }

    private func activateProfileFromContextMenu(_ candidate: DockProfile) {
        guard let current = store.state.profiles.first(where: { $0.id == candidate.id && $0.kind == candidate.kind }) else { return }
        if current.kind == .custom {
            store.activate(current.id)
            return
        }
        Task { @MainActor in
            do {
                try await NativeDockController.shared.apply(current)
                store.recordAppliedNativeProfile(current.id)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not switch the macOS Dock"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    var body: some View {
        let horizontal = settings.customDockPosition == .bottom
        let size = CGFloat(min(max(settings.customDockSize, 0.65), 1.5))
        GeometryReader { geometry in
            let contentLength = estimatedContentLength(size: size)
            let viewportLength = max(0, (horizontal ? geometry.size.width : geometry.size.height) - (settings.magnificationEnabled ? 32 : 22) * size)
            let needsJumpControls = DockOverflowPolicy.needsJumpControls(contentLength: contentLength,
                                                                         viewportLength: viewportLength)
            ScrollViewReader { proxy in
                Group {
                    if horizontal {
                        HStack(spacing: needsJumpControls ? 4 * size : 0) {
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: true, toEnd: false, size: size) }
                            DockScrollView(.horizontal) {
                                LazyHStack(spacing: CGFloat(settings.customDockItemSpacing) * size) { itemViews(horizontal: true, size: size) }
                                    .coordinateSpace(name: "dockItems")
                                    .onContinuousHover(coordinateSpace: .named("dockItems")) { phase in updateHover(phase, horizontal: true) }
                                    .padding(.horizontal, 1)
                            }
                            .scrollDisabled(popouts.anchorID != nil)
                            .scrollIndicators(.hidden)
                            .modifier(SizeBasedScrollBounce())
                            .modifier(DockScrollClip(horizontal: true, hoverInset: 32 * size))
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: true, toEnd: true, size: size) }
                        }
                    } else {
                        VStack(spacing: needsJumpControls ? 4 * size : 0) {
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: false, toEnd: false, size: size) }
                            DockScrollView(.vertical) {
                                LazyVStack(spacing: CGFloat(settings.customDockItemSpacing) * size) { itemViews(horizontal: false, size: size) }
                                    .coordinateSpace(name: "dockItems")
                                    .onContinuousHover(coordinateSpace: .named("dockItems")) { phase in updateHover(phase, horizontal: false) }
                                    .padding(.vertical, 1)
                            }
                            .scrollDisabled(popouts.anchorID != nil)
                            .scrollIndicators(.hidden)
                            .modifier(SizeBasedScrollBounce())
                            .modifier(DockScrollClip(horizontal: false, hoverInset: 32 * size))
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: false, toEnd: true, size: size) }
                        }
                    }
                }
                .padding((settings.magnificationEnabled ? 16 : 11) * size)
            }
        }
        .background {
            DockMaterialSurface(settings: settings, color: profileColor)
        }
        .animation(accessibility.reduceMotion || !settings.dockAnimationsEnabled ? nil : DockDesign.Motion.transform, value: profile.id)
        .animation(accessibility.reduceMotion || !settings.dockAnimationsEnabled ? nil : DockDesign.Motion.reorder, value: profile.items.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, settings.customDockTheme == .dark ? .dark : settings.customDockTheme == .light ? .light : settings.customDockMaterial == .dark ? .dark : systemAppearance.scheme)
        .contextMenu {
            if !isPreview {
                switchProfileMenu
                Divider()
                addToDockMenu
                Divider()
                Button("Settings…", systemImage: "gearshape") { openSettings(.dock) }
            }
        }
        .background {
            if !isPreview { Button("Close Popout") { popouts.dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
                .accessibilityHidden(true) }
        }
        .onAppear { if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() }
        }
        .onChange(of: profile.items) { _ in reconcilePopouts() }
        .onChange(of: settings.showTrash) { _ in reconcilePopouts() }
        .onChange(of: nowPlayingMonitor.runningSources) { _ in reconcilePopouts() }
        .onExitCommand { popouts.dismiss() }
        .onDisappear { if resizeStartSize != nil { store.finishDockResize(for: profile.id); DockInteractionState.isResizing = false } }
        .alert("Site Icon", isPresented: Binding(
            get: { linkIconMessage != nil },
            set: { if !$0 { linkIconMessage = nil } }
        )) {
            Button("OK", role: .cancel) { linkIconMessage = nil }
        } message: {
            Text(linkIconMessage ?? "")
        }
    }

    private func resizeGrip(horizontal: Bool) -> some View {
        let scale = CGFloat(settings.customDockSize)
        let layoutSize = DockResizeGripGeometry.layoutSize(horizontal: horizontal, scale: scale)
        let hitSize = DockResizeGripGeometry.hitSize(horizontal: horizontal, scale: scale)
        let outset = DockResizeGripGeometry.hitOutset(horizontal: horizontal, scale: scale)
        return RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(resizeGripHovered ? 0.45 : 0.20))
            .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
            .frame(width: layoutSize.width, height: layoutSize.height)
            .frame(width: hitSize.width, height: hitSize.height)
            .background(DockResizeCursor(horizontal: horizontal))
            .contentShape(Rectangle())
            .onHover { resizeGripHovered = $0 }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = resizeStartSize ?? CGFloat(settings.customDockSize)
                    resizeStartSize = start
                    let pointer = NSEvent.mouseLocation
                    let origin = resizeStartPointer ?? pointer
                    resizeStartPointer = origin
                    if !DockInteractionState.isResizing { PerformanceSignposts.event("DockResizeBegin") }
                    DockInteractionState.isResizing = true
                    let translation = CGSize(width: pointer.x - origin.x, height: origin.y - pointer.y)
                    let boundedSize = DockResizePolicy.size(start: start, translation: translation,
                                                           position: settings.customDockPosition)
                    guard abs(Double(boundedSize) - settings.customDockSize) >= 0.001 else { return }
                    store.previewDockSize(Double(boundedSize), for: profile.id)
                    resizeDidChange = true
                }
                .onEnded { _ in
                    resizeStartSize = nil
                    resizeStartPointer = nil
                    if resizeDidChange { store.finishDockResize(for: profile.id) }
                    PerformanceSignposts.event("DockResizeEnd")
                    DockInteractionState.isResizing = false
                    resizeDidChange = false
                })
            .onTapGesture(count: 2) { store.setDockSize(1, for: profile.id); store.flush() }
            // Enlarged pointer area only: layout length stays the visible grip's.
            .padding(.horizontal, -outset.width)
            .padding(.vertical, -outset.height)
            .help(horizontal ? "Drag up or down to resize. Double-click to reset size." : "Drag toward or away from the screen edge to resize. Double-click to reset size.")
            .accessibilityElement()
            .accessibilityLabel("Resize Custom Dock")
            .accessibilityValue("\(Int((settings.customDockSize * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                let delta: Double
                switch direction { case .increment: delta = 0.05; case .decrement: delta = -0.05; @unknown default: return }
                store.setDockSize(min(max(settings.customDockSize + delta, 0.65), 1.5), for: profile.id)
                store.flush()
            }
            .accessibilityAction(named: "Reset size") { store.setDockSize(1, for: profile.id); store.flush() }
    }

    private func estimatedContentLength(size: CGFloat) -> CGFloat {
        renderModel.contentLength(settings: settings, scale: size)
    }

    private func overflowJumpButton(proxy: ScrollViewProxy, horizontal: Bool, toEnd: Bool, size: CGFloat) -> some View {
        let symbol = horizontal
            ? (toEnd ? "chevron.right" : "chevron.left")
            : (toEnd ? "chevron.down" : "chevron.up")
        return Button {
            guard let targetID = (toEnd ? renderModel.entries.last : renderModel.entries.first)?.id else { return }
            let anchor: UnitPoint = horizontal
                ? (toEnd ? .trailing : .leading)
                : (toEnd ? .bottom : .top)
            if accessibility.reduceMotion {
                proxy.scrollTo(targetID, anchor: anchor)
            } else {
                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(targetID, anchor: anchor) }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11 * size, weight: .bold))
                .frame(width: 22 * size, height: 26 * size)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(popouts.anchorID != nil)
        .help(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
        .accessibilityLabel(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
    }


    private var profileColor: Color {
        (DockProfileColor(rawValue: profile.color) ?? .blue).displayColor
    }

    @ViewBuilder private func itemViews(horizontal: Bool, size: CGFloat) -> some View {
        ForEach(renderModel.positionedEntries(settings: settings, scale: size), id: \.visualID) { positioned in
            let entry = positioned.entry
            switch entry {
            case .item(let item, let pinned):
                if item.type == .spacer {
                    let spacer = RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.12))
                        .frame(width: horizontal ? entry.length(settings: settings, scale: size) : 42 * size,
                               height: horizontal ? 42 * size : entry.length(settings: settings, scale: size))
                        .accessibilityLabel(item.displayName)
                    if isPreview { spacer.allowsHitTesting(false) }
                    else { spacer
                        .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                        .dropDestination(for: DockDragPayload.self) { values, _ in handleTypedDrop(values, before: item.id) }
                    }
                } else {
                    itemView(item, horizontal: horizontal, size: size, pinned: pinned, center: positioned.center)
                        .matchedGeometryEffect(id: positioned.visualID, in: profileTransformation)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            case .insertion:
                Group {
                    if isPreview {
                        RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.20))
                            .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                            .frame(width: horizontal ? 14 * size : 42 * size, height: horizontal ? 42 * size : 14 * size)
                    } else { resizeGrip(horizontal: horizontal) }
                }
                    .contentShape(Rectangle())
                    .help(isPreview ? "Dock separator" : "Drag to resize the Dock. Drop items here to place them at the end of pinned items.")
                    .accessibilityLabel(isPreview ? "Dock separator" : "Resize Custom Dock")
                    .dropDestination(for: DockDropValue.self) { values, _ in
                        let items = values.compactMap { if case .items(let payload) = $0 { payload } else { nil } }
                        let urls = values.compactMap { if case .url(let url) = $0 { url } else { nil } }
                        let moved = !items.isEmpty && handleTypedDrop(items, before: nil)
                        let added = !urls.isEmpty && handleExternalDrop(urls)
                        return moved || added
                    }
            case .boundary(let kind):
                RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(kind == "running" ? 0 : 0.16))
                    .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                    .padding(.horizontal, horizontal ? 2 * size : 0)
                    .padding(.vertical, horizontal ? 0 : 2 * size)
                    .help(kind == "running" ? "Drop a pinned app here to unpin it" : "Minimized windows")
                    .dropDestination(for: DockDragPayload.self) { values, _ in
                        kind == "running" && handleTypedDrop(values, before: nil, unpin: true)
                    }
            case .window(let window):
                WindowDockTile(window: window, size: 48 * size, preview: windowMonitor.preview(for: window),
                               switchProfileMenu: AnyView(switchProfileMenu))
                    .scaleEffect(magnification(center: positioned.center, isWidget: false), anchor: magnificationAnchor)
            }
        }
    }

    @ViewBuilder private func itemView(_ item: DockItem, horizontal: Bool, size: CGFloat, pinned: Bool, center: CGFloat = 0) -> some View {
        let tileWidth = DockSurfaceMetrics.itemLength(item, settings: settings, scale: size)
        let tile = Button {
            guard !isPreview else { return }
            if item.type == .widget {
                if longPressTriggeredItemID == item.id {
                    longPressTriggeredItemID = nil
                    return
                }
                popouts.toggle(item.id)
            } else if item.type == .folder {
                if longPressTriggeredItemID == item.id {
                    longPressTriggeredItemID = nil
                    return
                }
                AppLauncher.open(item)
            }
            else {
                Task { @MainActor in
                    if settings.clickFocusedAppToMinimize, let identity = AppLauncher.runningIdentity(for: item),
                       await WindowAccessibilityService.minimizeFocusedWindow(of: identity) { return }
                    AppLauncher.open(item)
                }
            }
        } label: {
            Group {
                if item.type == .widget {
                    WidgetCompactView(store: store, item: item, profileID: profile.id, sampleMode: isPreview && !usesLivePreviewData, presentationSettings: settings)
                        .scaleEffect(size)
                        .frame(width: tileWidth, height: 54 * size)
                } else if item.type == .folder && item.showsFolderLabel {
                    VStack(spacing: 0) {
                        folderIconView(item, size: 40 * size)
                        Text(item.displayName)
                            .font(.system(size: 8 * size, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: tileWidth - 2 * size)
                    }
                    .frame(width: tileWidth, height: 54 * size)
                } else {
                    Group {
                        if item.type == .folder {
                            folderIconView(item, size: 48 * size)
                        } else if item.type == .file, item.url != nil {
                            DockFileThumbnailView(item: item, size: 48 * size)
                        } else if item.type == .application {
                            DockApplicationIconView(item: item, size: 48 * size)
                        } else {
                            Image(nsImage: AppLauncher.icon(for: item, size: 48 * size))
                                .resizable().scaledToFit().frame(width: 48 * size, height: 48 * size)
                        }
                    }
                    .frame(width: 48 * size, height: 48 * size)
                    .padding(3 * size)
                }
            }
            .frame(width: tileWidth, height: 54 * size)
            .background(popouts.tabIDs.contains(item.id) ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 13 * size))
            .overlay(alignment: .bottomTrailing) {
                if AppLauncher.isMissingTarget(item) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11 * size, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(2 * size)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.type == .application,
                   let bundleIdentifier = item.bundleIdentifier,
                   let badge = dockBadgeMonitor.badges[bundleIdentifier] {
                    Text(badge)
                        .font(.system(size: 10 * size, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5 * size)
                        .padding(.vertical, 2 * size)
                        .background(.red, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 0.75 * size))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: 4 * size, y: -2 * size)
                        .accessibilityLabel("Notification badge \(badge)")
                }
            }
            .help(AppLauncher.isMissingTarget(item) ? "\(item.displayName) · Saved location unavailable" : item.displayName)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLauncher.isMissingTarget(item)
            ? "Saved location unavailable. Re-add the item from its current location."
            : "")
        .scaleEffect(magnification(center: center, isWidget: item.type == .widget), anchor: magnificationAnchor)
        .zIndex(hoveredItemID == item.id ? 2 : 0)
        .onHover { isHovered in
            guard settings.magnificationEnabled,
                  !accessibility.reduceMotion else {
                hoveredItemID = nil
                return
            }
            hoveredItemID = isHovered ? item.id : nil
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard !isPreview, item.type == .folder else { return }
            longPressTriggeredItemID = item.id
            popouts.open(item.id)
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                if longPressTriggeredItemID == item.id { longPressTriggeredItemID = nil }
            }
        })
        .animation(accessibility.reduceMotion || !settings.dockAnimationsEnabled ? nil : .easeOut(duration: 0.12), value: hoverPosition == nil)
        .contextMenu {
            switchProfileMenu
            Divider()
            Button("Settings…", systemImage: "gearshape") { openSettings(.dock) }
            Divider()
            if item.type == .widget {
                Button("Configure Widget…") { popouts.open(item.id) }
                if item.id != systemTrashItem.id, settings.customDockPosition == .bottom {
                    Menu("Widget layout") {
                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { option in
                            Button(option.title) {
                                store.updateWidgetConfiguration(itemID: item.id, in: profile.id) { $0.widgetLayout = option.layout }
                            }
                        }
                    }
                }
                Button("Duplicate Widget", systemImage: "plus.square.on.square") {
                    store.duplicateWidget(item.id, in: profile.id)
                }
            } else if item.type == .folder {
                Button("Browse Contents") { popouts.open(item.id) }
                Button("Open in Finder") { AppLauncher.open(item) }
                Divider()
                Button("Customize Folder…", systemImage: "folder.badge.gearshape") { editFolderName(item) }
                Menu("Icon Color") {
                    ForEach(DockProfileColor.allCases) { color in
                        Button {
                            store.updateItem(item.id, in: profile.id) { $0.folderIconColor = color }
                        } label: {
                            if item.folderIconColor == color { Label(color.title, systemImage: "checkmark") }
                            else { Text(color.title) }
                        }
                    }
                }
                Button("Set Letter…") { editFolderLetter(item) }
                Toggle("Show Name Below Icon", isOn: Binding(
                    get: { item.showsFolderLabel },
                    set: { value in store.updateItem(item.id, in: profile.id) { $0.showFolderLabel = value } }
                ))
                Button("Reset Icon", role: .destructive) {
                    store.updateItem(item.id, in: profile.id) {
                        $0.folderIconColor = nil
                        $0.folderIconLetter = nil
                        $0.folderIconNumber = nil
                    }
                }
                .disabled(!item.hasCustomFolderIcon)
            } else if item.type == .link {
                Button("Rename Link…", systemImage: "pencil") { renameLink(item) }
                Button("Change Address…", systemImage: "link") { changeLinkAddress(item) }
                Menu("Choose Icon") {
                    Button("Site Icon or Default") {
                        store.updateItem(item.id, in: profile.id) { $0.linkIcon = nil }
                    }
                    ForEach(DockLinkIcon.allCases) { icon in
                        Button {
                            store.updateItem(item.id, in: profile.id) { $0.linkIcon = icon }
                        } label: {
                            if item.linkIcon == icon { Label(icon.title, systemImage: "checkmark") }
                            else { Label(icon.title, systemImage: icon.rawValue) }
                        }
                    }
                }
                Button("Fetch Site Icon…", systemImage: "globe") { fetchLinkIcon(item) }
                if item.linkFaviconData != nil {
                    Button("Remove Site Icon", role: .destructive) {
                        store.updateItem(item.id, in: profile.id) { $0.linkFaviconData = nil }
                    }
                }
            } else if item.type == .file, let fileURL = item.url {
                Button("Open") { AppLauncher.open(item) }
                Button("Reveal in Finder") {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                Button("Open Containing Folder") {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { return }
                    NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
                }
            } else {
                Button("Open") { AppLauncher.open(item) }
            }
            RunningApplicationMenuSection(item: item)
            if pinned, [.application, .file, .folder].contains(item.type) {
                Button("Locate…", systemImage: "folder.badge.questionmark") {
                    guard let repaired = AppLauncher.chooseReplacement(for: item) else { return }
                    store.updateItem(item.id, in: profile.id) { $0 = repaired }
                }
            }
            if pinned {
                Button("Remove from Dock", role: .destructive) { store.removeItem(item.id, from: profile.id) }
            } else {
                Button("Keep in Dock") { store.add(item, to: profile.id) }
            }
        }
        .popover(isPresented: Binding(get: { popouts.anchorID == item.id }, set: { if !$0 { popouts.dismiss() } }), arrowEdge: popoutArrowEdge) {
            if let activeItem = popoutItem(for: popouts.activeID) {
                VStack(alignment: .leading, spacing: 10) {
                    if openPopoutTabs.count > 1 { popoutTabBar }
                    DockScrollView(.vertical) {
                        if activeItem.type == .widget {
                            WidgetPopout(store: store, item: activeItem, profileID: profile.id)
                                .frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
                        } else if activeItem.type == .folder, let folderURL = activeItem.url {
                            FolderContentsPopout(folderURL: folderURL, folderName: activeItem.displayName) { popouts.dismiss() }
                        }
                    }
                }
                .padding(20)
                .background(WidgetDesign.surface)
                .preferredColorScheme(settings.customDockTheme == .system ? nil : settings.customDockTheme == .dark ? .dark : .light)
                .frame(minWidth: 250, minHeight: 150, maxHeight: popoutMaxHeight, alignment: .topLeading)
                .id(activeItem.id)
            }
        }
        .id(item.id.uuidString)

        if pinned, popouts.anchorID == nil, !isPreview {
            tile
                .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                .dropDestination(for: DockDragPayload.self) { values, _ in
                    handleTypedDrop(values, before: item.id)
                }
                .help("\(item.displayName) · Drag to reorder")
        } else if !isPreview, !pinned, item.type == .application,
                  popouts.anchorID == nil {
            tile.allowsHitTesting(!isPreview)
                .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                .dropDestination(for: DockDragPayload.self) { values, _ in
                    handleTypedDrop(values, before: nil, unpin: true)
                }
        } else {
            tile.allowsHitTesting(!isPreview).accessibilityHidden(isPreview)
        }
    }

    @ViewBuilder private func folderIconView(_ item: DockItem, size: CGFloat) -> some View {
        if item.hasCustomFolderIcon {
            DockFolderIconView(item: item, size: size)
        } else {
            Image(nsImage: AppLauncher.icon(for: item, size: size))
                .resizable().scaledToFit().frame(width: size, height: size)
        }
    }

    private func editFolderName(_ item: DockItem) {
        let alert = NSAlert()
        alert.messageText = "Customize Folder"
        alert.informativeText = "Choose a name shown in this Dock. Clear the field to use the folder’s Finder name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = item.folderCustomName ?? item.title
        field.placeholderString = item.title
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Name")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateItem(item.id, in: profile.id) { $0.folderCustomName = name.isEmpty ? nil : name }
    }

    private func editFolderLetter(_ item: DockItem) {
        let alert = NSAlert()
        alert.messageText = "Folder Icon Letter"
        alert.informativeText = "Enter one optional letter, or clear the field to remove it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        field.stringValue = item.folderIconLetter ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Letter")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let letter = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        store.updateItem(item.id, in: profile.id) { $0.folderIconLetter = letter.isEmpty ? nil : letter }
    }

    private var renderModel: DockRenderModel {
        DockRenderModel(profile: profile, settings: settings, runningApplications: runningApps.map(\.item),
                        windows: isPreview && !usesLivePreviewData ? [] : windowMonitor.windows, runningMediaSources: isPreview && !usesLivePreviewData ? Set(NowPlayingSource.allCases) : nowPlayingMonitor.runningSources)
    }

    private var magnificationAnchor: UnitPoint {
        switch settings.customDockPosition {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private func updateHover(_ phase: HoverPhase, horizontal: Bool) {
        switch phase {
        case .active(let location): hoverPosition = horizontal ? location.x : location.y
        case .ended: hoverPosition = nil
        }
    }

    private func magnification(center: CGFloat, isWidget: Bool) -> CGFloat {
        if isWidget { return 1 }
        let scale = CGFloat(settings.customDockSize)
        guard !isPreview, popouts.anchorID == nil else { return 1 }
        return DockContinuousMagnification.scale(center: center, pointer: hoverPosition, radius: 150 * scale,
            isWidget: isWidget, enabled: settings.magnificationEnabled, reduceMotion: accessibility.reduceMotion)
    }

    private func handleTypedDrop(_ values: [DockDragPayload], before targetID: UUID?, unpin: Bool = false) -> Bool {
        guard !isPreview, popouts.anchorID == nil, let value = values.first else { return false }
        if let bundleID = value.runningBundleIdentifier {
            // Compatibility with older drag producers: only an unambiguous
            // installed copy may be pinned by a bundle-only payload.
            let matches = runningApps.filter { $0.item.bundleIdentifier == bundleID }
            guard !unpin, matches.count == 1 else { return false }
            store.insert(matches[0].item, before: targetID, in: profile.id)
            return true
        }
        guard value.profileID == profile.id, !value.itemIDs.isEmpty else { return false }
        let running = runningApps.filter { value.itemIDs.contains($0.item.id) }
        if !running.isEmpty {
            guard !unpin, running.count == value.itemIDs.count else { return false }
            for app in running { store.insert(app.item, before: targetID, in: profile.id) }
            return true
        }
        if unpin {
            let apps = profile.items.filter { value.itemIDs.contains($0.id) && $0.type == .application }
            guard !apps.isEmpty else { return false }
            store.removeItems(Set(apps.map(\.id)), from: profile.id)
        } else {
            store.moveItems(Set(value.itemIDs), before: targetID, in: profile.id)
        }
        return true
    }

    private func handleExternalDrop(_ urls: [URL]) -> Bool {
        guard !isPreview, popouts.anchorID == nil else { return false }
        var added = false
        for url in urls.prefix(100) {
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                store.add(url.pathExtension == "app" ? .application(at: url) : .file(at: url, isFolder: folder), to: profile.id)
                added = true
            } else if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                store.add(.link(url, title: url.host ?? url.absoluteString), to: profile.id)
                added = true
            }
        }
        return added
    }

    private var popoutArrowEdge: Edge {
        switch settings.customDockPosition {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var openPopoutTabs: [DockItem] {
        popouts.tabIDs.compactMap { popoutItem(for: $0) }
    }

    private var popoutTabBar: some View {
        DockScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(openPopoutTabs) { tab in
                    HStack(spacing: 2) {
                        Button(tab.displayName) { popouts.select(tab.id) }
                            .buttonStyle(.bordered)
                            .tint(popouts.activeID == tab.id ? Color.accentColor : Color.gray.opacity(0.8))
                            .lineLimit(1)
                        Button {
                            popouts.close(tab.id)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Close \(tab.displayName)")
                        .accessibilityLabel("Close \(tab.displayName)")
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 28)
    }

    private func popoutItem(for itemID: UUID?) -> DockItem? {
        guard let itemID else { return nil }
        if let item = visibleProfileItems.first(where: { $0.id == itemID }) { return item }
        return systemTrashItem.id == itemID ? systemTrashItem : nil
    }

    private func reconcilePopouts() {
        var validIDs = Set(visibleProfileItems.map(\.id))
        if CustomDockVisibilityPolicy.showsSystemTrash(
            isEnabled: settings.showTrash,
            hasProfileTrashWidget: profile.items.contains(where: { $0.widgetKind == "Trash" })
        ) {
            validIDs.insert(systemTrashItem.id)
        }
        popouts.retain(only: validIDs)
    }

    private var visibleProfileItems: [DockItem] {
        profile.items.filter { item in
            guard item.widgetKind == "Now Playing" else { return true }
            let configuration = item.widgetConfiguration ?? WidgetConfiguration()
            return NowPlayingVisibilityPolicy.showsTile(
                hideWhenClosed: configuration.nowPlayingHidesWhenClosed,
                enabledSources: Set(configuration.nowPlayingEnabledSources),
                runningSources: nowPlayingMonitor.runningSources)
        }
    }

    private var runningApps: [RunningDockApp] {
        guard !isPreview || usesLivePreviewData else { return [] }
        return RuntimeDockIdentity.unpinned(runtimeApplications, pinnedURLs: RuntimeDockApplications.pinnedURLs(in: profile))
            .map { RunningDockApp(id: $0.id.uuidString, item: $0) }
    }
}

private struct WindowDockTile: View {
    var window: DockWindowDescriptor
    var size: CGFloat
    var preview: NSImage?
    var switchProfileMenu: AnyView

    private var icon: NSImage {
        if let identity = window.applicationIdentity,
           let application = WindowAccessibilityService.currentApplication(matches: identity),
           let bundleURL = application.bundleURL {
            return AppLauncher.icon(for: .application(at: bundleURL), size: size)
        }
        return NSImage(systemSymbolName: "macwindow", accessibilityDescription: window.title)
            ?? NSImage(size: NSSize(width: size, height: size))
    }

    var body: some View {
        Button { WindowAccessibilityService.activate(window) } label: {
            Group {
                if let preview {
                    Image(nsImage: preview).resizable().scaledToFit()
                        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.09), lineWidth: 0.5))
                } else {
                    Image(nsImage: icon).resizable().scaledToFit()
                }
            }
                .frame(width: size, height: size)
                .padding(3)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(window.isMinimized ? Color.orange : Color.green)
                        .frame(width: 7, height: 7).overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
                }
        }
        .buttonStyle(.plain)
        .help("\(window.title) · \(window.applicationName)")
        .accessibilityLabel("\(window.isMinimized ? "Minimized window" : "Window"): \(window.title), \(window.applicationName)")
        .contextMenu {
            Button("Restore Window") { WindowAccessibilityService.activate(window) }
            Button("Close Window") { WindowAccessibilityService.close(window) }
                .disabled(!WindowAccessibilityService.isTrusted())
            if let identity = window.applicationIdentity {
                Button("Quit \(window.applicationName)") { AppLauncher.quit(identity) }
            }
            Divider()
            switchProfileMenu
        }
    }
}

private struct SizeBasedScrollBounce: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

private struct RunningDockApp: Identifiable {
    var id: String
    var item: DockItem
}

private struct DockScrollClip: ViewModifier {
    var horizontal: Bool
    var hoverInset: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.scrollClipDisabled()
                .mask {
                    // Keep scrolling items within the viewport while allowing
                    // magnification to grow toward the desktop on the other axis.
                    Rectangle().padding(horizontal ? .vertical : .horizontal, -hoverInset)
                }
        } else {
            content
        }
    }
}
