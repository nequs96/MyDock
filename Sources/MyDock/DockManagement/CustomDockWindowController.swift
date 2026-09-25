import AppKit
import Combine
import SwiftUI

@MainActor
final class CustomDockWindowController {
    private var panel: NSPanel?
    private var observation: AnyCancellable?
    private var screenObservation: AnyCancellable?
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
    private var pendingRevealTask: Task<Void, Never>?
    private let store: ProfileStore

    init(store: ProfileStore) {
        self.store = store
        observation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.update(state: state)
        }
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
    }

    func update(state: PersistentState) {
        guard state.settings.setupMode != .nativeOnly,
              let profileID = state.settings.activeCustomProfileID,
              let profile = state.profiles.first(where: { $0.id == profileID && $0.kind == .custom }) else {
            SystemActivityMonitor.shared.setDockVisible(false)
            NetworkActivityMonitor.shared.setDockVisible(false)
            NowPlayingMonitor.shared.setDockVisible(false)
            RefreshScheduler.shared.setDockVisible(false)
            WindowAccessibilityMonitor.shared.setEnabled(false)
            panel?.orderOut(nil)
            revealPanel?.orderOut(nil)
            stopMouseMonitoring()
            stopProfileGestureMonitoring()
            return
        }
        guard let screen = screen(for: state.settings) else { return }
        currentPosition = state.settings.customDockPosition
        currentColor = DockProfileColor(rawValue: profile.color) ?? .blue
        let root = CustomDockView(store: store, profile: profile)
        if let panel, let hosting = panel.contentView as? NSHostingView<CustomDockView> {
            hosting.rootView = root
            expandedFrame = place(panel, on: screen, itemCount: profile.items.count, settings: state.settings)
        } else {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 84),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: root)
            self.panel = panel
            expandedFrame = place(panel, on: screen, itemCount: profile.items.count, settings: state.settings)
        }
        updateRevealPanel(on: screen)
        configureWindowMode(desktop: state.settings.customDockDesktopMode)
        startProfileGestureMonitoring()
        if (state.settings.automaticallyHideCustomDock && !state.settings.customDockDesktopMode)
            || state.settings.hideCustomDockWhenSystemDockAppears {
            startMouseMonitoring()
            updateAutoHide(mouseLocation: NSEvent.mouseLocation)
        } else {
            stopMouseMonitoring()
            revealPanel?.orderOut(nil)
            panel?.orderFrontRegardless()
            SystemActivityMonitor.shared.setDockVisible(true)
            NetworkActivityMonitor.shared.setDockVisible(true)
            NowPlayingMonitor.shared.setDockVisible(true)
            RefreshScheduler.shared.setDockVisible(true)
            configureWindowMonitoring(state.settings)
        }
    }

    private func screen(for settings: AppSettings) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == settings.customDockDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func place(_ panel: NSPanel, on screen: NSScreen, itemCount: Int, settings: AppSettings) -> NSRect {
        let visible = screen.visibleFrame
        let scale = CGFloat(min(max(settings.customDockSize, 0.65), 1.5))
        let iconLength = 48 * scale
        let itemLength = CGFloat(max(itemCount, 1)) * (iconLength + 8 * scale) + 22 * scale
        let maxLength = settings.customDockPosition == .bottom ? visible.width - 40 : visible.height - 60
        let length = min(max(itemLength, 100), max(maxLength, 100))
        let frame: NSRect
        switch settings.customDockPosition {
        case .bottom:
            let width = length
            let height = iconLength + 22 * scale
            frame = NSRect(x: visible.midX - width / 2, y: visible.minY + 10, width: width, height: height)
        case .left:
            let width = iconLength + 22 * scale
            let height = length
            frame = NSRect(x: visible.minX + 10, y: visible.midY - height / 2, width: width, height: height)
        case .right:
            let width = iconLength + 22 * scale
            let height = length
            frame = NSRect(x: visible.maxX - width - 10, y: visible.midY - height / 2, width: width, height: height)
        }
        panel.setFrame(frame, display: true, animate: false)
        return frame
    }

    private func updateRevealPanel(on screen: NSScreen) {
        let handleSize: CGFloat = 6
        let handleLength: CGFloat = 38
        let visible = screen.visibleFrame
        switch currentPosition {
        case .bottom:
            revealFrame = NSRect(x: visible.midX - handleLength / 2, y: visible.minY + 1, width: handleLength, height: handleSize)
        case .left:
            revealFrame = NSRect(x: visible.minX + 1, y: visible.midY - handleLength / 2, width: handleSize, height: handleLength)
        case .right:
            revealFrame = NSRect(x: visible.maxX - handleSize - 1, y: visible.midY - handleLength / 2, width: handleSize, height: handleLength)
        }

        let content = RevealHandleView(position: currentPosition, color: color(for: currentColor))
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
    }

    private func handleProfileGesture(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas,
              let panel,
              event.window === panel else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            perpendicularSwipeDelta = 0
            parallelSwipeDelta = 0
        }

        let isHorizontal = currentPosition == .bottom
        let perpendicularDelta = isHorizontal ? event.scrollingDeltaY : event.scrollingDeltaX
        let parallelDelta = isHorizontal ? event.scrollingDeltaX : event.scrollingDeltaY
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

        if let currentIndex = store.customProfiles.firstIndex(where: { $0.id == store.state.settings.activeCustomProfileID }),
           let destination = DockProfileSwipePolicy.destinationIndex(currentIndex: currentIndex,
                                                                      perpendicularDelta: perpendicularSwipeDelta + perpendicularDelta,
                                                                      parallelDelta: parallelSwipeDelta + parallelDelta,
                                                                      profileCount: store.customProfiles.count) {
            store.activate(store.customProfiles[destination].id)
        }
        perpendicularSwipeDelta = 0
        parallelSwipeDelta = 0
    }

    private func updateAutoHide(mouseLocation: NSPoint) {
        guard let panel else { return }
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
        if CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: mouseLocation,
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
        guard pendingRevealTask == nil else { return }
        pendingRevealTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }
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
        revealPanel?.orderOut(nil)
        panel?.orderFrontRegardless()
        SystemActivityMonitor.shared.setDockVisible(true)
        NetworkActivityMonitor.shared.setDockVisible(true)
        NowPlayingMonitor.shared.setDockVisible(true)
        RefreshScheduler.shared.setDockVisible(true)
        configureWindowMonitoring(store.state.settings)
    }

    private func configureWindowMonitoring(_ settings: AppSettings) {
        WindowAccessibilityMonitor.shared.setEnabled(
            settings.showMinimizedWindows || settings.clickFocusedAppToMinimize,
            previewsEnabled: settings.showMinimizedWindows && settings.showWindowPreviews
        )
    }

    private func hideDockPanel() {
        panel?.orderOut(nil)
        revealPanel?.orderFrontRegardless()
        SystemActivityMonitor.shared.setDockVisible(false)
        NetworkActivityMonitor.shared.setDockVisible(false)
        NowPlayingMonitor.shared.setDockVisible(false)
        RefreshScheduler.shared.setDockVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
    }

    private func hideDockPanelForSystemDock() {
        panel?.orderOut(nil)
        revealPanel?.orderOut(nil)
        SystemActivityMonitor.shared.setDockVisible(false)
        NetworkActivityMonitor.shared.setDockVisible(false)
        NowPlayingMonitor.shared.setDockVisible(false)
        RefreshScheduler.shared.setDockVisible(false)
        WindowAccessibilityMonitor.shared.setEnabled(false)
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

enum CustomDockVisibilityPolicy {
    static func showsSystemTrash(isEnabled: Bool, hasProfileTrashWidget: Bool) -> Bool {
        isEnabled && !hasProfileTrashWidget
    }

    static func shouldReveal(mouseLocation: NSPoint,
                             expandedFrame: NSRect,
                             revealFrame: NSRect,
                             popoutFrames: [NSRect] = []) -> Bool {
        shouldRevealImmediately(mouseLocation: mouseLocation,
                                expandedFrame: expandedFrame,
                                popoutFrames: popoutFrames)
            || isAtRevealEdge(mouseLocation: mouseLocation, revealFrame: revealFrame)
    }

    static func shouldRevealImmediately(mouseLocation: NSPoint,
                                       expandedFrame: NSRect,
                                       popoutFrames: [NSRect] = []) -> Bool {
        expandedFrame.insetBy(dx: -10, dy: -10).contains(mouseLocation)
            || popoutFrames.contains { $0.insetBy(dx: -6, dy: -6).contains(mouseLocation) }
    }

    static func isAtRevealEdge(mouseLocation: NSPoint, revealFrame: NSRect) -> Bool {
        revealFrame.insetBy(dx: -6, dy: -6).contains(mouseLocation)
    }

    static func shouldHideForSystemDock(customDockFrame: NSRect, systemDockFrames: [NSRect]) -> Bool {
        SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDockFrame,
                                                     systemDockFrames: systemDockFrames)
    }
}

enum DockProfileSwipePolicy {
    static func destinationIndex(currentIndex: Int,
                                 perpendicularDelta: CGFloat,
                                 parallelDelta: CGFloat,
                                 profileCount: Int) -> Int? {
        guard profileCount > 1,
              (0..<profileCount).contains(currentIndex),
              abs(perpendicularDelta) >= 48,
              abs(perpendicularDelta) > abs(parallelDelta) * 1.2 else { return nil }
        let direction = perpendicularDelta > 0 ? 1 : -1
        return (currentIndex + direction + profileCount) % profileCount
    }
}

enum DockOverflowPolicy {
    static func needsJumpControls(contentLength: CGFloat, viewportLength: CGFloat) -> Bool {
        contentLength > viewportLength + 1
    }
}

struct DockPopoutSelection: Equatable {
    private(set) var anchorID: UUID?
    private(set) var activeID: UUID?
    private(set) var tabIDs: [UUID] = []

    mutating func toggle(_ itemID: UUID) {
        if activeID == itemID {
            dismiss()
        } else {
            open(itemID)
        }
    }

    mutating func open(_ itemID: UUID) {
        if !tabIDs.contains(itemID) { tabIDs.append(itemID) }
        if anchorID == nil { anchorID = itemID }
        activeID = itemID
    }

    mutating func select(_ itemID: UUID) {
        guard tabIDs.contains(itemID) else { return }
        activeID = itemID
    }

    mutating func close(_ itemID: UUID) {
        tabIDs.removeAll { $0 == itemID }
        if tabIDs.isEmpty {
            dismiss()
            return
        }
        if activeID == itemID { activeID = tabIDs.last }
        if anchorID == itemID { anchorID = activeID ?? tabIDs.first }
    }

    mutating func retain(only validIDs: Set<UUID>) {
        tabIDs.removeAll { !validIDs.contains($0) }
        if tabIDs.isEmpty {
            dismiss()
            return
        }
        if activeID.map({ !validIDs.contains($0) }) ?? true { activeID = tabIDs.last }
        if anchorID.map({ !validIDs.contains($0) }) ?? true { anchorID = activeID ?? tabIDs.first }
    }

    mutating func dismiss() {
        anchorID = nil
        activeID = nil
        tabIDs.removeAll()
    }
}

enum DockMagnification {
    static func scale(for itemIndex: Int, focusedIndex: Int, isWidget: Bool = false,
                      enabled: Bool, reduceMotion: Bool) -> CGFloat {
        guard enabled, !reduceMotion else { return 1 }
        let distance = abs(itemIndex - focusedIndex)
        guard distance <= 2 else { return 1 }
        let applicationIntensity: CGFloat = distance == 0 ? 0.38 : distance == 1 ? 0.2 : 0.08
        let intensity = isWidget ? applicationIntensity * 0.55 : applicationIntensity
        return 1 + intensity
    }
}

private struct RevealHandleView: View {
    var position: DockPosition
    var color: Color
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    var body: some View {
        Capsule()
            .fill(accessibility.reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(Capsule().fill(color.opacity(accessibility.reduceTransparency ? 1 : 0.65)))
            .padding(position == .bottom ? .horizontal : .vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
    }
}

struct CustomDockView: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    @State private var popouts = DockPopoutSelection()
    @State private var systemTrashItem = DockItem.widget("Trash")
    @State private var hoveredItemID: UUID?
    @State private var longPressTriggeredItemID: UUID?
    @State private var resizeStartSize: CGFloat?
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared
    @ObservedObject private var windowMonitor = WindowAccessibilityMonitor.shared
    @ObservedObject private var nowPlayingMonitor = NowPlayingMonitor.shared

    @ViewBuilder private var switchProfileMenu: some View {
        Menu("Switch Profile") {
            if !store.nativeProfiles.isEmpty {
                Menu("macOS Dock") {
                    ForEach(store.nativeProfiles) { candidate in
                        profileMenuButton(candidate, isActive: store.state.settings.activeNativeProfileID == candidate.id)
                    }
                }
            }
            if !store.customProfiles.isEmpty {
                Menu("Custom Dock") {
                    ForEach(store.customProfiles) { candidate in
                        profileMenuButton(candidate, isActive: store.state.settings.activeCustomProfileID == candidate.id)
                    }
                }
            }
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
                store.activate(current.id)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not switch the macOS Dock"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    var body: some View {
        let horizontal = store.state.settings.customDockPosition == .bottom
        let size = CGFloat(min(max(store.state.settings.customDockSize, 0.65), 1.5))
        GeometryReader { geometry in
            let contentLength = estimatedContentLength(size: size)
            let viewportLength = max(0, (horizontal ? geometry.size.width : geometry.size.height) - 22 * size)
            let needsJumpControls = DockOverflowPolicy.needsJumpControls(contentLength: contentLength,
                                                                         viewportLength: viewportLength)
            ScrollViewReader { proxy in
                Group {
                    if horizontal {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8 * size) { itemViews(horizontal: true, size: size) }
                                .padding(.horizontal, 1)
                        }
                        .scrollIndicators(.hidden)
                        .modifier(SizeBasedScrollBounce())
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 8 * size) { itemViews(horizontal: false, size: size) }
                                .padding(.vertical, 1)
                        }
                        .scrollIndicators(.hidden)
                        .modifier(SizeBasedScrollBounce())
                    }
                }
                .padding(11 * size)
                .overlay(alignment: horizontal ? .leading : .top) {
                    if needsJumpControls {
                        overflowJumpButton(proxy: proxy, horizontal: horizontal, toEnd: false)
                            .padding(horizontal ? .leading : .top, 2 * size)
                    }
                }
                .overlay(alignment: horizontal ? .trailing : .bottom) {
                    if needsJumpControls {
                        overflowJumpButton(proxy: proxy, horizontal: horizontal, toEnd: true)
                            .padding(horizontal ? .trailing : .bottom, 2 * size)
                    }
                }
            }
        }
        .background {
            ZStack {
                dockSurface
                if !accessibility.reduceTransparency && store.state.settings.customDockMaterial == .frosted {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(profileColor.opacity(0.2))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accessibility.increaseContrast ? Color.primary.opacity(0.8) : Color.primary.opacity(0.22),
                        lineWidth: accessibility.increaseContrast ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu { switchProfileMenu }
        .overlay(alignment: horizontal ? .topTrailing : .bottomTrailing) {
            resizeGrip(horizontal: horizontal).padding(5)
        }
        .animation(accessibility.reduceMotion ? nil : .snappy(duration: 0.2), value: profile.items)
        .background {
            Button("Close Popout") { popouts.dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
        .onChange(of: profile.items) { _ in reconcilePopouts() }
        .onChange(of: store.state.settings.showTrash) { _ in reconcilePopouts() }
        .onChange(of: nowPlayingMonitor.runningSources) { _ in reconcilePopouts() }
        .onExitCommand { popouts.dismiss() }
    }

    private func resizeGrip(horizontal: Bool) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = resizeStartSize ?? CGFloat(store.state.settings.customDockSize)
                    resizeStartSize = start
                    let delta = horizontal ? value.translation.width : value.translation.height
                    let steppedSize = ((start + delta / 180) * 20).rounded() / 20
                    let boundedSize = min(max(steppedSize, 0.65), 1.5)
                    guard abs(Double(boundedSize) - store.state.settings.customDockSize) >= 0.049 else { return }
                    store.updateSettings { $0.customDockSize = Double(boundedSize) }
                }
                .onEnded { _ in resizeStartSize = nil })
            .help("Drag to resize the Custom Dock")
            .accessibilityElement()
            .accessibilityLabel("Resize Custom Dock")
    }

    private func estimatedContentLength(size: CGFloat) -> CGFloat {
        var lengths = visibleProfileItems.map { item -> CGFloat in
            item.type == .spacer ? (item.spacerKind == .small ? 8 : 18) * size : 54 * size
        }
        if CustomDockVisibilityPolicy.showsSystemTrash(
            isEnabled: store.state.settings.showTrash,
            hasProfileTrashWidget: profile.items.contains(where: { $0.widgetKind == "Trash" })
        ) {
            lengths.append(54 * size)
        }
        let apps = store.state.settings.showRunningApps ? runningApps.count : 0
        let windows = store.state.settings.showMinimizedWindows ? windowMonitor.windows.filter(\.isMinimized).count : 0
        if apps > 0 {
            lengths.append(5 * size)
            lengths.append(contentsOf: repeatElement(54 * size, count: apps))
        }
        if windows > 0 {
            lengths.append(5 * size)
            lengths.append(contentsOf: repeatElement(48 * size + 6, count: windows))
        }
        let spacing = CGFloat(max(0, lengths.count - 1)) * 8 * size
        return lengths.reduce(0, +) + spacing + 2
    }

    private func overflowJumpButton(proxy: ScrollViewProxy, horizontal: Bool, toEnd: Bool) -> some View {
        let symbol = horizontal
            ? (toEnd ? "chevron.right" : "chevron.left")
            : (toEnd ? "chevron.down" : "chevron.up")
        return Button {
            let targetID: String?
            if toEnd {
                if store.state.settings.showMinimizedWindows,
                   let lastWindow = windowMonitor.windows.last(where: \.isMinimized) {
                    targetID = lastWindow.id
                } else if store.state.settings.showRunningApps, let lastApp = runningApps.last {
                    targetID = lastApp.id
                } else if CustomDockVisibilityPolicy.showsSystemTrash(
                    isEnabled: store.state.settings.showTrash,
                    hasProfileTrashWidget: profile.items.contains(where: { $0.widgetKind == "Trash" })
                ) {
                    targetID = systemTrashItem.id.uuidString
                } else {
                    targetID = visibleProfileItems.last?.id.uuidString
                }
            } else if let firstItem = visibleProfileItems.first {
                targetID = firstItem.id.uuidString
            } else if CustomDockVisibilityPolicy.showsSystemTrash(
                isEnabled: store.state.settings.showTrash,
                hasProfileTrashWidget: profile.items.contains(where: { $0.widgetKind == "Trash" })
            ) {
                targetID = systemTrashItem.id.uuidString
            } else if store.state.settings.showRunningApps, let firstApp = runningApps.first {
                targetID = firstApp.id
            } else {
                targetID = windowMonitor.windows.first(where: \.isMinimized)?.id
            }
            guard let targetID else { return }
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
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 26)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
        .accessibilityLabel(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
    }

    @ViewBuilder private var dockSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if accessibility.reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            switch store.state.settings.customDockMaterial {
            case .frosted:
                shape.fill(.ultraThinMaterial)
            case .dark:
                shape.fill(Color.black.opacity(0.72))
            case .liquidGlass:
                if #available(macOS 26.0, *) {
                    shape.fill(.clear).glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
        }
    }

    private var profileColor: Color {
        switch DockProfileColor(rawValue: profile.color) ?? .blue {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }

    @ViewBuilder private func itemViews(horizontal: Bool, size: CGFloat) -> some View {
        ForEach(visibleProfileItems) { item in
            if item.type == .spacer {
                RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.12))
                    .frame(width: horizontal ? (item.spacerKind == .small ? 8 : 18) * size : 42 * size,
                           height: horizontal ? 42 * size : (item.spacerKind == .small ? 8 : 18) * size)
                    .accessibilityLabel(item.title)
                    .id(item.id.uuidString)
            } else {
                itemView(item, horizontal: horizontal, size: size, pinned: true)
            }
        }
        if CustomDockVisibilityPolicy.showsSystemTrash(
            isEnabled: store.state.settings.showTrash,
            hasProfileTrashWidget: profile.items.contains(where: { $0.widgetKind == "Trash" })
        ) {
            itemView(systemTrashItem, horizontal: horizontal, size: size, pinned: false)
        }
        if store.state.settings.showRunningApps, !runningApps.isEmpty {
            RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.16))
                .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                .padding(.horizontal, horizontal ? 2 : 0)
                .padding(.vertical, horizontal ? 0 : 2)
                .accessibilityHidden(true)
            ForEach(runningApps) { runningApp in
                itemView(runningApp.item, horizontal: horizontal, size: size, pinned: false)
                    .id(runningApp.id)
            }
        }
        let minimizedWindows = windowMonitor.windows.filter(\.isMinimized)
        if store.state.settings.showMinimizedWindows, !minimizedWindows.isEmpty {
            RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.16))
                .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                .padding(.horizontal, horizontal ? 2 : 0)
                .padding(.vertical, horizontal ? 0 : 2)
                .accessibilityHidden(true)
            ForEach(minimizedWindows) { window in
                WindowDockTile(window: window,
                               size: 48 * size,
                               preview: windowMonitor.preview(for: window),
                               switchProfileMenu: AnyView(switchProfileMenu)).id(window.id)
            }
        }
    }

    @ViewBuilder private func itemView(_ item: DockItem, horizontal: Bool, size: CGFloat, pinned: Bool) -> some View {
        Button {
            if item.type == .widget || item.type == .folder {
                if longPressTriggeredItemID == item.id {
                    longPressTriggeredItemID = nil
                    return
                }
                popouts.toggle(item.id)
            }
            else if store.state.settings.clickFocusedAppToMinimize,
                    let bundleIdentifier = item.bundleIdentifier,
                    WindowAccessibilityService.minimizeFocusedWindow(of: bundleIdentifier) { return }
            else { AppLauncher.open(item) }
        } label: {
            Group {
                if item.type == .widget {
                    WidgetCompactView(store: store, item: item, profileID: profile.id)
                } else if item.type == .folder && item.hasCustomFolderIcon {
                    DockFolderIconView(item: item, size: 48 * size)
                } else if item.type == .file, item.url != nil {
                    DockFileThumbnailView(item: item, size: 48 * size)
                } else {
                    Image(nsImage: AppLauncher.icon(for: item, size: 48 * size))
                        .resizable().scaledToFit().frame(width: 48 * size, height: 48 * size)
                }
            }
            .frame(width: 48 * size, height: 48 * size)
            .padding(3 * size)
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
            .help(AppLauncher.isMissingTarget(item) ? "\(item.title) · Saved location unavailable" : item.title)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLauncher.isMissingTarget(item)
            ? "Saved location unavailable. Re-add the item from its current location."
            : "")
        .scaleEffect(magnification(for: item))
        .zIndex(hoveredItemID == item.id ? 2 : 0)
        .onHover { isHovered in
            guard store.state.settings.magnificationEnabled,
                  !accessibility.reduceMotion else {
                hoveredItemID = nil
                return
            }
            hoveredItemID = isHovered ? item.id : nil
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard item.type == .folder else { return }
            longPressTriggeredItemID = item.id
            popouts.open(item.id)
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                if longPressTriggeredItemID == item.id { longPressTriggeredItemID = nil }
            }
        })
        .animation(accessibility.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: hoveredItemID)
        .contextMenu {
            switchProfileMenu
            Divider()
            if item.type == .widget {
                Button("Configure Widget…") { popouts.open(item.id) }
            } else if item.type == .folder {
                Button("Browse Folder") { popouts.open(item.id) }
                Button("Open in Finder") { AppLauncher.open(item) }
            } else if item.type == .file, let fileURL = item.url {
                Button("Open") { AppLauncher.open(item) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                Button("Open Containing Folder") { NSWorkspace.shared.open(fileURL.deletingLastPathComponent()) }
            } else {
                Button("Open") { AppLauncher.open(item) }
            }
            if let bundleIdentifier = item.bundleIdentifier {
                let appWindows = windowMonitor.windows.filter { $0.bundleIdentifier == bundleIdentifier }
                if !appWindows.isEmpty {
                    Menu("Windows") {
                        ForEach(appWindows) { window in
                            Button("\(window.isMinimized ? "Restore" : "Activate"): \(window.title)") {
                                WindowAccessibilityService.activate(window)
                            }
                        }
                    }
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
                    if activeItem.type == .widget {
                        WidgetPopout(store: store, item: activeItem, profileID: profile.id)
                            .frame(minWidth: 250, minHeight: 150)
                    } else if activeItem.type == .folder, let folderURL = activeItem.url {
                        FolderContentsPopout(folderURL: folderURL) { popouts.dismiss() }
                    }
                }
                .padding(16)
                .frame(minWidth: 250, minHeight: 150)
                .id(activeItem.id)
            }
        }
        .id(item.id.uuidString)
    }

    private func magnification(for item: DockItem) -> CGFloat {
        guard store.state.settings.magnificationEnabled,
              !accessibility.reduceMotion,
              let hoveredItemID,
              let focusedIndex = profile.items.firstIndex(where: { $0.id == hoveredItemID }),
              let itemIndex = profile.items.firstIndex(where: { $0.id == item.id }) else { return 1 }
        return DockMagnification.scale(for: itemIndex, focusedIndex: focusedIndex,
                                       isWidget: item.type == .widget,
                                       enabled: true, reduceMotion: false)
    }

    private var popoutArrowEdge: Edge {
        switch store.state.settings.customDockPosition {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var openPopoutTabs: [DockItem] {
        popouts.tabIDs.compactMap { popoutItem(for: $0) }
    }

    private var popoutTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(openPopoutTabs) { tab in
                    HStack(spacing: 2) {
                        Button(tab.title) { popouts.select(tab.id) }
                            .buttonStyle(.bordered)
                            .tint(popouts.activeID == tab.id ? Color.accentColor : Color.gray.opacity(0.8))
                            .lineLimit(1)
                        Button {
                            popouts.close(tab.id)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Close \(tab.title)")
                        .accessibilityLabel("Close \(tab.title)")
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
            isEnabled: store.state.settings.showTrash,
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
                source: configuration.nowPlayingSource,
                runningSources: nowPlayingMonitor.runningSources)
        }
    }

    private var runningApps: [RunningDockApp] {
        let pinnedBundleIDs = Set(profile.items.compactMap(\.bundleIdentifier))
        let descriptors = NSWorkspace.shared.runningApplications.compactMap { application -> RunningApplicationDescriptor? in
            guard let identifier = application.bundleIdentifier, let url = application.bundleURL else { return nil }
            return RunningApplicationDescriptor(bundleIdentifier: identifier,
                                                name: application.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                                bundleURL: url,
                                                isRegularApplication: application.activationPolicy == .regular,
                                                isTerminated: application.isTerminated)
        }
        return RunningApplicationFilter.visible(descriptors, excluding: pinnedBundleIDs).map { descriptor in
            var item = DockItem.application(at: descriptor.bundleURL)
            item.title = descriptor.name
            item.bundleIdentifier = descriptor.bundleIdentifier
            return RunningDockApp(id: descriptor.bundleIdentifier, item: item)
        }
    }
}

private struct WindowDockTile: View {
    var window: DockWindowDescriptor
    var size: CGFloat
    var preview: NSImage?
    var switchProfileMenu: AnyView

    private var icon: NSImage {
        if let application = NSRunningApplication(processIdentifier: window.processID),
           let bundleURL = application.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
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
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
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
