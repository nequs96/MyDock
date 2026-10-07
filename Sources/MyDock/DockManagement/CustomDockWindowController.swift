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
    private var presentationVisible = false
    private var lastPresentation: DockPresentationSignature?
    private var transitionGeneration = UUID()
    private var transitionInFlight: DockTransitionPolicy.Snapshot?
    private var applicationObservation: AnyCancellable?
    private var profileGestureMonitor: Any?
    private var revealPanel: NSPanel?
    private var expandedFrame = NSRect.zero
    private var revealFrame = NSRect.zero
    private var currentPosition: DockPosition = .bottom
    /// The resolved floating inset of the presented profile; reveal decisions extend
    /// the keep-visible area back over this gap to the screen edge.
    private var currentFloatingInset: Double = 0
    private var perpendicularSwipeDelta: CGFloat = 0
    private var parallelSwipeDelta: CGFloat = 0
    private var commandScrollDelta: CGFloat = 0
    private var usingDisplayFallback = false
    private var noScreenAvailable = false
    /// One queued update stands for every runtime publication that arrives before it runs.
    private var updateScheduled = false
    private let store: ProfileStore
    private let openSettings: (MyDockSettingsPage) -> Void
    private let overviewIsPresent: (NSRect, [NSRect]) -> Bool
    private lazy var revealMonitor = DockRevealMonitor(snapshot: { [weak self] _ in
        self?.revealSnapshot()
    }, present: { [weak self] decision in
        guard let self else { return }
        switch decision {
        case .show: self.showDockPanel()
        case .hide, .dwell: self.hideDockPanel()
        case .suppress: self.hideDockPanelForSystemDock()
        }
    }, ownsMenuWindow: { [weak self] window in
        guard let self else { return false }
        var candidate: NSWindow? = window
        while let current = candidate {
            if current === self.panel || current === self.revealPanel { return true }
            candidate = current.parent
        }
        return false
    })

    init(store: ProfileStore, openSettings: @escaping (MyDockSettingsPage) -> Void = { _ in },
         overviewIsPresent: @escaping (NSRect, [NSRect]) -> Bool = { SystemOverviewPolicy.isPresent(screen: $0, dockFrames: $1) }) {
        self.store = store
        self.openSettings = openSettings
        self.overviewIsPresent = overviewIsPresent
        DockWindowPreviewController.shared.openSettings = openSettings
        _ = store.widgetLifecycle
        observation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.update(state: state)
        }
        runtimeObservations.append(store.runtimeCache.$entries.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Cache publication updates the observed faces. Geometry-only signatures
                // keep the current hosting root intact when readings change.
                self?.scheduleUpdate()
            })
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
                self?.scheduleUpdate()
            }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        applicationObservation = Publishers.Merge(
            workspaceNotifications.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspaceNotifications.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.scheduleUpdate()
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
            // Only minimized windows are Dock tiles; title churn in other windows changes no layout.
            WindowAccessibilityMonitor.shared.$windows.map { $0.filter(\.isMinimized) }.removeDuplicates().dropFirst()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleUpdate() }
                },
            NowPlayingMonitor.shared.$runningSources.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleUpdate() }
            },
            RecentApplicationsTracker.shared.$recents.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleUpdate() }
            }
        ]
    }

    /// Runtime publications (readings, windows, app launches, screens) arrive in bursts. Each burst
    /// runs one update with the latest state instead of one full layout pass per event.
    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            updateScheduled = false
            update(state: store.state)
        }
    }

    /// Orders both panels out and stops everything that runs only while the Dock is presented. Bumps the
    /// transition generation and cancels a running fade, so a reveal in flight cannot finish on a hidden panel.
    private func tearDownPresentation() {
        setLiveMonitorsVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
        DockWindowPreviewController.shared.dockDidHide()
        lastPresentation = nil
        presentationVisible = false
        transitionGeneration = UUID()
        transitionInFlight = nil
        if let panel {
            panel.contentView?.layer?.removeAnimation(forKey: "dockPresentationScale")
            // Setting the property directly under a zero-duration group cancels the running animator animation.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                panel.animator().alphaValue = 0
            }
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
        revealPanel?.orderOut(nil)
        revealMonitor.stop()
        stopProfileGestureMonitoring()
    }

    func update(state: PersistentState) {
        WindowAccessibilityMonitor.shared.setPreviewCacheRetentionEnabled(
            state.settings.showMinimizedWindows && state.settings.showWindowPreviews
        )
        DockBadgeMonitor.shared.setEnabled(state.settings.showAppBadges)
        RecentApplicationsTracker.shared.setEnabled(state.settings.showRecentApps)
        DockWindowPreviewController.shared.setEnabled(state.settings.showWindowPreviewsOnHover)
        guard state.settings.setupMode != .nativeOnly,
              let profileID = state.settings.activeCustomProfileID,
              let authoredProfile = state.profiles.first(where: { $0.id == profileID && $0.kind == .custom }) else {
            usingDisplayFallback = false
            noScreenAvailable = false
            tearDownPresentation()
            return
        }
        let profile = store.presentationProfile(authoredProfile)
        guard let screen = screen(for: state.settings) else {
            tearDownPresentation()
            return
        }
        // The preview subscriber owns frame changes during a drag. Replacing
        // rootView here can interrupt the gesture and restart live monitors.
        if DockInteractionState.isResizing, lastPresentation?.profileID == profile.id { return }
        let resolvedSettings = store.effectiveSettings(for: profile)
        let runtimeApplications = RuntimeDockApplications.items()
        let pinnedApplicationURLs = RuntimeDockApplications.pinnedURLs(in: profile)
        let layout = DockRenderModel(profile: profile, settings: resolvedSettings,
            runningApplications: runtimeApplications, windows: WindowAccessibilityMonitor.shared.windows,
            runningMediaSources: NowPlayingMonitor.shared.runningSources,
            pinnedApplicationURLs: pinnedApplicationURLs,
            recentApplications: RuntimeDockApplications.recentItems(profile: profile, settings: resolvedSettings,
                runtime: runtimeApplications, pinnedURLs: pinnedApplicationURLs))
        let signature = DockPresentationSignature(profileID: profile.id, color: profile.color, settings: DockPresentationSettings(resolvedSettings), global: DockPresentationSettings(state.settings),
            displayFrame: screen.visibleFrame, entries: layout.entries.map { "\($0.id):\($0.length(settings: resolvedSettings, scale: 1))" })
        reconcileTransition(settings: state.settings)
        guard signature != lastPresentation else { return }
        let resizing = lastPresentation?.settings.size != resolvedSettings.customDockSize
        lastPresentation = signature
        currentPosition = resolvedSettings.customDockPosition
        let root = CustomDockView(store: store, profile: profile, openSettings: openSettings)
        if let panel, let hosting = panel.contentView as? DockSurfaceHostingView<CustomDockView> {
            PerformanceSignposts.measure("DockRootAssignment") { hosting.rootView = root }
#if DEBUG
            PerformanceSignposts.noteRootAssignment()
#endif
            hosting.surfaceCornerRadius = CGFloat(resolvedSettings.customDockCornerRadius)
            expandedFrame = place(panel, on: screen, profile: profile, settings: resolvedSettings, model: layout, animate: !resizing)
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
            expandedFrame = place(panel, on: screen, profile: profile, settings: resolvedSettings, model: layout)
        }
        revealMonitor.startSampling()
        updateRevealPanel(on: screen, shouldShowHandle: state.settings.showRevealHandle)
        configureWindowMode(desktop: state.settings.customDockDesktopMode,
                            autoHide: state.settings.automaticallyHideCustomDock)
        startProfileGestureMonitoring()
        if (state.settings.automaticallyHideCustomDock && !state.settings.customDockDesktopMode)
            || state.settings.hideCustomDockWhenSystemDockAppears {
            revealMonitor.startPointerMonitoring()
            revealMonitor.sample()
        } else {
            revealMonitor.stopPointerMonitoring()
            revealPanel?.orderOut(nil)
            presentDock(visible: true)
            setLiveMonitorsVisible(true)
            configureWindowMonitoring(state.settings)
        }
    }

    private func screen(for settings: AppSettings) -> NSScreen? {
        let (screen, fallback) = DockDisplaySelection.screen(selectedID: settings.customDockDisplayID)
        if fallback && !usingDisplayFallback {
            DiagnosticsService.shared.record(.customDockDisplayFallback)
        } else if !fallback && usingDisplayFallback {
            DiagnosticsService.shared.record(.customDockDisplayRestored)
        }
        usingDisplayFallback = fallback
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

    /// `model` is the layout `update` already built for these settings; the resize preview passes none.
    private func place(_ panel: NSPanel, on screen: NSScreen, profile: DockProfile, settings: AppSettings,
                       model prebuilt: DockRenderModel? = nil, animate: Bool = false) -> NSRect {
        let visible = dockPlacementFrame(on: screen)
        let scale = DockSurfaceMetrics.clampedScale(settings.customDockSize)
        let tileLength = (54 + (DockMagnificationSupport.isActive(settings) ? 22 : 0)) * scale
        let model: DockRenderModel
        if let prebuilt {
            model = prebuilt
        } else {
            let runtimeApplications = RuntimeDockApplications.items()
            let pinnedApplicationURLs = RuntimeDockApplications.pinnedURLs(in: profile)
            model = DockRenderModel(profile: profile, settings: settings, runningApplications: runtimeApplications,
                                    windows: WindowAccessibilityMonitor.shared.windows,
                                    runningMediaSources: NowPlayingMonitor.shared.runningSources,
                                    pinnedApplicationURLs: pinnedApplicationURLs,
                                    recentApplications: RuntimeDockApplications.recentItems(profile: profile, settings: settings,
                                        runtime: runtimeApplications, pinnedURLs: pinnedApplicationURLs))
        }
        let itemLength = model.contentLength(settings: settings, scale: scale) + (DockMagnificationSupport.isActive(settings) ? 32 : 22) * scale
        let frame = DockPanelGeometry.frame(position: settings.customDockPosition, placementArea: visible,
                                            contentLength: itemLength, crossLength: tileLength + 22 * scale,
                                            floatingInset: settings.customDockFloatingInset)
        currentFloatingInset = settings.customDockFloatingInset
        if animate && presentationVisible && settings.dockAnimationsEnabled && !AccessibilityDisplayState.shared.reduceMotion {
            // The animator runs alongside the main thread; setFrame(_:display:animate:) would block it for the resize.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        return frame
    }

    private func updateRevealPanel(on screen: NSScreen, shouldShowHandle: Bool) {
        // The reveal strip stays at the screen edge whatever the floating inset.
        revealFrame = DockPanelGeometry.revealFrame(position: currentPosition, placementArea: dockPlacementFrame(on: screen))

        let content = RevealHandleView(position: currentPosition, isVisible: shouldShowHandle)
        if let revealPanel {
            if let hosting = revealPanel.contentView as? NSHostingView<RevealHandleView> {
                hosting.rootView = content
            } else {
                revealPanel.contentView = NSHostingView(rootView: content)
            }
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

    private func configureWindowMode(desktop: Bool, autoHide: Bool) {
        // Desktop mode sits just above Finder's desktop-icon window, so clicks reach the Dock rather than Finder,
        // and stays put through Mission Control and Show Desktop.
        let level = desktop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) : .floating
        let behavior: NSWindow.CollectionBehavior = desktop
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle]
            : DockWindowSpacePolicy.collectionBehavior(autoHide: autoHide)
        panel?.isFloatingPanel = !desktop
        panel?.level = level
        panel?.collectionBehavior = behavior
        revealPanel?.isFloatingPanel = !desktop
        revealPanel?.level = level
        revealPanel?.collectionBehavior = behavior
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

    private func revealSnapshot() -> DockRevealMonitor.Snapshot? {
        // Queued pointer events can outlive mode/profile changes.
        guard canPresentDock, let panel else { return nil }
        let settings = store.state.settings
        let retainsInteraction = revealMonitor.menuTrackingDepth > 0 || DockInteractionState.isResizing
        // Preserve the existing precedence: menu/resize retention bypasses native sampling.
        let dockFrames = retainsInteraction ? [] : SystemDockVisibilityReader.visibleDockFrames()
        let overviewPresent = !retainsInteraction && screen(for: settings).map {
            overviewIsPresent($0.frame, dockFrames)
        } == true
        let overlaps = !retainsInteraction && !overviewPresent && settings.hideCustomDockWhenSystemDockAppears
            && SystemDockVisibilityReader.isVisible(overlapping: expandedFrame)
        return DockRevealMonitor.Snapshot(canPresent: true, retainsInteraction: retainsInteraction,
            overviewPresent: overviewPresent, systemDockOverlaps: overlaps,
            desktopMode: settings.customDockDesktopMode, autoHide: settings.automaticallyHideCustomDock,
            visible: presentationVisible, mouseLocation: NSEvent.mouseLocation,
            expandedFrame: DockPanelGeometry.hoverFrame(expanded: expandedFrame, position: currentPosition,
                                                        floatingInset: currentFloatingInset),
            revealFrame: revealFrame, popoutFrames: (panel.childWindows ?? []).map(\.frame))
    }

    private func showDockPanel() {
        guard canPresentDock else { return }
        if panel?.isVisible == false { DiagnosticsService.shared.record(.customDockShown) }
        revealPanel?.orderOut(nil)
        presentDock(visible: true)
        setLiveMonitorsVisible(true)
        configureWindowMonitoring(store.state.settings)
    }

    private var canPresentDock: Bool {
        CustomDockVisibilityPolicy.canPresent(mode: store.state.settings.setupMode,
                                             hasActiveProfile: store.activeCustomProfile != nil)
    }

    /// Everything that samples only while the Dock is on screen. One list, so a new live widget cannot be
    /// left out of an auto-hide or hide-for-Apple-Dock path again.
    private func setLiveMonitorsVisible(_ visible: Bool) {
        SystemActivityMonitor.shared.setDockVisible(visible)
        NetworkActivityMonitor.shared.setDockVisible(visible)
        NowPlayingMonitor.shared.setDockVisible(visible)
        AudioOutputService.shared.setDockVisible(visible)
        RefreshScheduler.shared.setDockVisible(visible)
        store.widgetData.setVisible(visible)
        DockBadgeMonitor.shared.setDockVisible(visible)
    }

    private func configureWindowMonitoring(_ settings: AppSettings) {
        // Click-to-minimize reads the focused window on demand; only minimized-window tiles need sampling.
        WindowAccessibilityMonitor.shared.setEnabled(
            settings.showMinimizedWindows,
            previewsEnabled: settings.showMinimizedWindows && settings.showWindowPreviews
        )
    }

    private func hideDockPanel() {
        if panel?.isVisible == true { DiagnosticsService.shared.record(.customDockHidden) }
        presentDock(visible: false)
        revealPanel?.orderFrontRegardless()
        setLiveMonitorsVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
        DockWindowPreviewController.shared.dockDidHide()
    }

    private func hideDockPanelForSystemDock() {
        if panel?.isVisible == true { DiagnosticsService.shared.record(.customDockHidden) }
        presentDock(visible: false)
        revealPanel?.orderOut(nil)
        setLiveMonitorsVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
        DockWindowPreviewController.shared.dockDidHide()
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
}

/// Which Spaces the floating Custom Dock joins.
enum DockWindowSpacePolicy {
    /// Like Apple's Dock, an always-visible Custom Dock stays out of full-screen Spaces instead of covering
    /// the app's content; an auto-hiding one joins them and reveals at the screen edge.
    static func collectionBehavior(autoHide: Bool) -> NSWindow.CollectionBehavior {
        autoHide ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle] : [.canJoinAllSpaces, .ignoresCycle]
    }
}
