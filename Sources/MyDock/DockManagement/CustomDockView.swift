import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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


/// A slim, quiet capsule at the screen edge of an auto-hidden Dock. Increase Contrast makes
/// it thicker and stronger; Reduce Transparency draws it opaque.
struct RevealHandleView: View {
    var position: DockPosition
    var isVisible: Bool
    @DockAccessibilityStyle() private var accessibility

    private var thickness: CGFloat { accessibility.contrast == .increased ? 4 : 3 }
    private var fill: Color {
        DockDesign.DockChrome.revealHandle(accessibility.contrast, reduceTransparency: accessibility.reduceTransparency)
    }

    var body: some View {
        Group {
            if isVisible {
                Capsule()
                    .fill(fill)
                    .frame(width: position == .bottom ? nil : thickness, height: position == .bottom ? thickness : nil)
                    .padding(position == .bottom ? .horizontal : .vertical, 4)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { if DockInteractionState.isResizing { $0.animation = nil } }
        .background(Color.clear)
    }
}

/// Values one Dock body pass reads for every tile, computed once per pass: the projected profile,
/// its effective settings and the render model each rebuild every item.
private struct DockPass {
    var profile: DockProfile
    var settings: AppSettings
    var model: DockRenderModel
    var runningPinnedIDs: Set<UUID>
    var recentIDs: Set<UUID>
    var runningBundleIdentifiers: Set<String>
}

struct CustomDockView: View {
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    private var sourceProfile: DockProfile
    /// Recomputed on every read: body passes read `DockPass.profile` instead; actions read this.
    var profile: DockProfile {
        isPreview ? sourceProfile : store.presentationProfile(store.state.profiles.first(where: { $0.id == sourceProfile.id }) ?? sourceProfile)
    }
    var isPreview = false
    var usesLivePreviewData = false

    init(store: ProfileStore, profile: DockProfile, isPreview: Bool = false, usesLivePreviewData: Bool = false,
         openSettings: @escaping (MyDockSettingsPage) -> Void = { _ in }) {
        self.store = store
        runtimeCache = store.runtimeCache
        sourceProfile = profile
        self.isPreview = isPreview
        self.usesLivePreviewData = usesLivePreviewData
        self.openSettings = openSettings
    }
    /// Recomputed on every read: body passes read `DockPass.settings` instead; actions read this.
    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    var openSettings: (MyDockSettingsPage) -> Void = { _ in }
    @Namespace private var profileTransformation
    @State private var popouts = DockPopoutSelection()
    private var systemTrashItem: DockItem { DockRenderModel.systemTrash }
    @State private var hoverPosition: CGFloat?
    @State private var runtimeApplications: [DockItem] = []
    /// Running-app matches, recomputed only when the running apps or the pinned apps change.
    @State private var runningAppCache = DockRunningAppCache(resolve: { AppLauncher.resolvedURL(for: $0) })
    /// Items whose saved target is missing. Checking touches the file system, so it is refreshed on
    /// item, app-launch and volume changes rather than on every hover/magnification re-render.
    @State private var missingTargetIDs: Set<UUID> = []
    @State private var hoveredItemID: UUID?
    @State private var longPressTriggeredItemID: UUID?
    @State private var resizeStartSize: CGFloat?
    @State private var resizeStartPointer: NSPoint?
    @State private var resizeDidChange = false
    @State private var resizeGripHovered = false
    @State private var linkIconMessage: String?
    /// The media players that are running. Only this changes the Dock, so the Dock reads it alone
    /// instead of observing every Now Playing snapshot and artwork update.
    @State private var runningMediaSources: Set<NowPlayingSource> = NowPlayingMonitor.shared.runningSources
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared
    @DockAccessibilityStyle() private var accessibilityStyle
    @Namespace private var popoutGlass
    #if DEBUG
    @Environment(\.dockPreviewRunningBundleIdentifiers) private var previewRunningBundleIdentifiers
    @Environment(\.dockPreviewBadges) private var previewBadges
    @Environment(\.dockPreviewActivePopoutAnchor) private var previewActivePopoutAnchor
    #endif
    /// Items just dropped into a new place; they settle back to full size on `Motion.morph`.
    @State private var settlingItemIDs: Set<UUID> = []
    @ObservedObject private var windowMonitor = WindowAccessibilityMonitor.shared
    @ObservedObject private var dockBadgeMonitor = DockBadgeMonitor.shared
    @ObservedObject private var recentApplicationsTracker = RecentApplicationsTracker.shared
    /// The application tile a Finder drag is hovering, highlighted like a selected tile.
    @State private var dropTargetedItemID: UUID?

    private func popoutMaxHeight(displayID: UInt32?) -> CGFloat {
        let screen = DockDisplaySelection.screen(selectedID: displayID).screen
        let visibleHeight = screen?.visibleFrame.height ?? 720
        return min(600, max(180, visibleHeight - 160))
    }

    /// Profile choices show the active one with the menu's native checkmark.
    @ViewBuilder private func switchProfileMenu(settings: AppSettings) -> some View {
        Menu("Switch Dock") {
            if !store.nativeProfiles.isEmpty {
                Menu("macOS Dock") {
                    ForEach(store.nativeProfiles) { candidate in
                        profileMenuToggle(candidate, isActive: settings.activeNativeProfileID == candidate.id)
                    }
                }
            }
            if !store.customProfiles.isEmpty {
                Menu("Custom Dock") {
                    ForEach(store.customProfiles) { candidate in
                        profileMenuToggle(candidate, isActive: settings.activeCustomProfileID == candidate.id)
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
                Button("Add \(kind.title.capitalized)") { store.add(.spacer(kind), to: profile.id) }
            }
        }
    }

    private func chooseApplication() {
        guard let url = DockItemPrompts.chooseApplication() else { return }
        store.add(.application(at: url), to: profile.id)
    }

    private func chooseFolder() {
        guard let url = DockItemPrompts.chooseFolder() else { return }
        store.add(.file(at: url, isFolder: true), to: profile.id)
    }

    private func chooseFile() {
        guard let url = DockItemPrompts.chooseFile() else { return }
        store.add(.file(at: url), to: profile.id)
    }

    private func addWebLink() {
        guard let url = DockItemPrompts.webLink() else { return }
        store.add(.link(url, title: ""), to: profile.id)
    }

    private func renameLink(_ item: DockItem) {
        guard let title = DockItemPrompts.linkName(for: item) else { return }
        let fallback = item.url?.host ?? item.url?.absoluteString ?? item.title
        store.updateItem(item.id, in: profile.id) { $0.title = title.isEmpty ? fallback : String(title.prefix(120)) }
    }

    private func changeLinkAddress(_ item: DockItem) {
        guard let url = DockItemPrompts.linkAddress(for: item) else { return }
        let previousHost = item.url?.host?.lowercased()
        let previousDefaultTitle = item.url?.host
        store.updateItem(item.id, in: profile.id) { current in
            current.url = url
            if current.title == previousDefaultTitle, let newHost = url.host { current.title = newHost }
            if previousHost != url.host?.lowercased() { current.linkFaviconData = nil }
        }
    }

    /// A fetched icon simply appears on the tile; only a failure explains itself.
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
        }
    }

    private func profileMenuToggle(_ candidate: DockProfile, isActive: Bool) -> some View {
        Toggle(candidate.name, isOn: Binding(
            get: { isActive },
            set: { if $0 { activateProfileFromContextMenu(candidate) } }
        ))
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
                DockItemPrompts.showError("Could not switch the macOS Dock", error.localizedDescription)
            }
        }
    }

    var body: some View {
        let pass = makePass()
        let settings = pass.settings
        let horizontal = settings.customDockPosition == .bottom
        let size = DockSurfaceMetrics.clampedScale(settings.customDockSize)
        let padding = DockSurfaceMetrics.padding(settings: settings, scale: size)
        GeometryReader { geometry in
            let contentLength = estimatedContentLength(pass, size: size)
            let viewportLength = max(0, (horizontal ? geometry.size.width : geometry.size.height) - 2 * padding)
            let needsJumpControls = DockOverflowPolicy.needsJumpControls(contentLength: contentLength,
                                                                         viewportLength: viewportLength)
            ScrollViewReader { proxy in
                Group {
                    if horizontal {
                        HStack(spacing: needsJumpControls ? 4 * size : 0) {
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: true, toEnd: false, size: size) }
                            DockScrollView(.horizontal) {
                                LazyHStack(spacing: CGFloat(settings.customDockItemSpacing) * size) { itemViews(pass, horizontal: true, size: size) }
                                    .coordinateSpace(name: "dockItems")
                                    .onContinuousHover(coordinateSpace: .named("dockItems")) { phase in updateHover(phase, horizontal: true) }
                                    .padding(.horizontal, 1)
                                    .modifier(DockItemStackPresentation(glassGroup: usesGlassGroup(settings),
                                        moduleRadius: DockSurfaceMetrics.moduleRadius(settings: settings, scale: size)))
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
                                LazyVStack(spacing: CGFloat(settings.customDockItemSpacing) * size) { itemViews(pass, horizontal: false, size: size) }
                                    .coordinateSpace(name: "dockItems")
                                    .onContinuousHover(coordinateSpace: .named("dockItems")) { phase in updateHover(phase, horizontal: false) }
                                    .padding(.vertical, 1)
                                    .modifier(DockItemStackPresentation(glassGroup: usesGlassGroup(settings),
                                        moduleRadius: DockSurfaceMetrics.moduleRadius(settings: settings, scale: size)))
                            }
                            .scrollDisabled(popouts.anchorID != nil)
                            .scrollIndicators(.hidden)
                            .modifier(SizeBasedScrollBounce())
                            .modifier(DockScrollClip(horizontal: false, hoverInset: 32 * size))
                            if needsJumpControls { overflowJumpButton(proxy: proxy, horizontal: false, toEnd: true, size: size) }
                        }
                    }
                }
                .padding(padding)
            }
        }
        .background {
            DockMaterialSurface(settings: settings, color: profileColor(pass.profile))
        }
        .animation(DockMotionPolicy.profileTransformAnimation(reduceMotion: reducesMotion, animationsEnabled: settings.dockAnimationsEnabled), value: pass.profile.id)
        .animation(DockMotionPolicy.reorderAnimation(reduceMotion: reducesMotion, animationsEnabled: settings.dockAnimationsEnabled), value: pass.profile.items.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, DockColorSchemePolicy.scheme(theme: settings.customDockTheme, material: settings.customDockMaterial,
                                                                  system: systemAppearance.scheme))
        .contextMenu {
            if !isPreview {
                switchProfileMenu(settings: settings)
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
        .onAppear {
            if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() }
            refreshMissingTargets()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() }
            refreshMissingTargets()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            if !isPreview || usesLivePreviewData { runtimeApplications = RuntimeDockApplications.items() }
            refreshMissingTargets()
        }
        .onReceive(NowPlayingMonitor.shared.$runningSources.removeDuplicates()) { runningMediaSources = $0 }
        .onChange(of: pass.profile.items) { _ in reconcilePopouts(); refreshMissingTargets() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshMissingTargets() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshMissingTargets() }
        .onChange(of: settings.showTrash) { _ in reconcilePopouts() }
        .onChange(of: runningMediaSources) { _ in reconcilePopouts() }
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

    /// Reads the live settings, not a pass snapshot: the drag compares against each resize step.
    private func resizeGrip(horizontal: Bool, showsLine: Bool) -> some View {
        let scale = DockSurfaceMetrics.clampedScale(settings.customDockSize)
        let layoutSize = DockResizeGripGeometry.layoutSize(horizontal: horizontal, scale: scale)
        let hitSize = DockResizeGripGeometry.hitSize(horizontal: horizontal, scale: scale)
        let outset = DockResizeGripGeometry.hitOutset(horizontal: horizontal, scale: scale)
        let contrast = accessibilityStyle.contrast
        return RoundedRectangle(cornerRadius: 1)
            .fill(resizeGripHovered ? DockDesign.DockChrome.separatorHighlight(contrast)
                  : showsLine ? DockDesign.DockChrome.separator(contrast) : Color.clear)
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
                store.setDockSize(Double(DockSurfaceMetrics.clampedScale(settings.customDockSize + delta)), for: profile.id)
                store.flush()
            }
            .accessibilityAction(named: "Reset size") { store.setDockSize(1, for: profile.id); store.flush() }
    }

    private func estimatedContentLength(_ pass: DockPass, size: CGFloat) -> CGFloat {
        isPreview ? DockSeparatorPolicy.previewContentLength(pass.model.entries, settings: pass.settings, scale: size)
            : pass.model.contentLength(settings: pass.settings, scale: size)
    }

    /// The entries drawn: previews end at their last tile (`DockSeparatorPolicy.previewCollapsedEntryIDs`).
    private func drawnEntries(_ model: DockRenderModel) -> [DockRenderEntry] {
        guard isPreview else { return model.entries }
        let collapsed = DockSeparatorPolicy.previewCollapsedEntryIDs(model.entries)
        return model.entries.filter { !collapsed.contains($0.id) }
    }

    private func overflowJumpButton(proxy: ScrollViewProxy, horizontal: Bool, toEnd: Bool, size: CGFloat) -> some View {
        let symbol = horizontal
            ? (toEnd ? "chevron.right" : "chevron.left")
            : (toEnd ? "chevron.down" : "chevron.up")
        let contrast = accessibilityStyle.contrast
        return Button {
            let entries = drawnEntries(makePass().model)
            guard let targetID = (toEnd ? entries.last : entries.first)?.id else { return }
            let anchor: UnitPoint = horizontal
                ? (toEnd ? .trailing : .leading)
                : (toEnd ? .bottom : .top)
            DockDesign.Motion.perform(DockDesign.Motion.disclosure,
                                      reduceMotion: reducesMotion || !settings.dockAnimationsEnabled) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11 * size, weight: .bold))
                .frame(width: 22 * size, height: 26 * size)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(DockDesign.Outline.color(contrast), lineWidth: DockDesign.Outline.controlWidth(contrast)))
        }
        .buttonStyle(.plain)
        .disabled(popouts.anchorID != nil)
        .help(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
        .accessibilityLabel(toEnd ? "Jump to end of Dock" : "Jump to start of Dock")
    }


    private func profileColor(_ profile: DockProfile) -> Color {
        (DockProfileColor(rawValue: profile.color) ?? .blue).displayColor
    }

    /// One glass container around the items on macOS 26 so glass widget modules blend
    /// and morph with each other. Reduce Transparency and non-glass materials skip it.
    /// The Dock surface stays outside it: see `DockGlassComposition`.
    private func usesGlassGroup(_ settings: AppSettings) -> Bool {
        DockGlassComposition.scope(material: settings.customDockMaterial,
                                   reduceTransparency: accessibilityStyle.reduceTransparency) == .itemStack
    }

    /// The system setting and the render-only accessibility preview both stop Dock motion.
    private var reducesMotion: Bool { accessibility.reduceMotion || accessibilityStyle.reduceMotion }

    /// The module a popout hangs from: the live anchor, or a render-only fixture in previews.
    private func isActivePopoutAnchor(_ item: DockItem) -> Bool {
        #if DEBUG
        if isPreview, let previewActivePopoutAnchor { return previewActivePopoutAnchor == item.id }
        #endif
        return !isPreview && popouts.anchorID == item.id
    }

    /// Dropped items dip slightly and settle on `Motion.morph`; nothing moves under Reduce Motion.
    private func settle(_ itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty,
              let animation = DockMotionPolicy.settleAnimation(reduceMotion: reducesMotion,
                                                               animationsEnabled: settings.dockAnimationsEnabled) else { return }
        settlingItemIDs = itemIDs
        DispatchQueue.main.async { withAnimation(animation) { settlingItemIDs = [] } }
    }

    /// The projected profile, its settings and the render model, built once for a body pass.
    private func makePass() -> DockPass {
        let profile = self.profile
        let settings = store.effectiveSettings(for: profile)
        let matches = runningMatches(profile: profile)
        let recent = recentApplicationItems(profile: profile, settings: settings, matches: matches)
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: matches.unpinnedRuntime,
                                    windows: isPreview && !usesLivePreviewData ? [] : windowMonitor.windows,
                                    runningMediaSources: isPreview && !usesLivePreviewData ? Set(NowPlayingSource.allCases) : runningMediaSources,
                                    recentApplications: recent)
        return DockPass(profile: profile, settings: settings, model: model,
                        runningPinnedIDs: runningPinnedItemIDs(profile: profile, matches: matches),
                        recentIDs: Set(recent.map(\.id)),
                        runningBundleIdentifiers: Set(runtimeApplications.compactMap(\.bundleIdentifier)))
    }

    /// Pinned apps whose installed copy is running. Unpinned runtime entries are running by construction.
    private func runningPinnedItemIDs(profile: DockProfile, matches: DockRunningAppMatches) -> Set<UUID> {
        #if DEBUG
        if isPreview && !usesLivePreviewData, let identifiers = previewRunningBundleIdentifiers {
            return Set(profile.items.filter { $0.type == .application && identifiers.contains($0.bundleIdentifier ?? "") }.map(\.id))
        }
        #endif
        return matches.runningPinnedItemIDs
    }

    /// Cached: body evaluations (hover, magnification) compare inputs and normalize no URL.
    private func runningMatches(profile: DockProfile) -> DockRunningAppMatches {
        guard !isPreview || usesLivePreviewData else { return DockRunningAppMatches() }
        return runningAppCache.matches(runtime: runtimeApplications, profileItems: profile.items)
    }

    /// Recent, unpinned apps (the optional section after the running apps). None in previews.
    private func recentApplicationItems(profile: DockProfile, settings: AppSettings, matches: DockRunningAppMatches) -> [DockItem] {
        guard !isPreview, settings.showRecentApps else { return [] }
        return RuntimeDockApplications.recentItems(profile: profile, settings: settings, runtime: runtimeApplications,
                                                   pinnedURLs: matches.pinnedURLs)
    }

    private func refreshMissingTargets() {
        missingTargetIDs = DockMissingTargets.ids(in: profile.items, isMissing: AppLauncher.isMissingTarget)
    }

    private func badge(for item: DockItem) -> String? {
        guard item.type == .application, let bundleIdentifier = item.bundleIdentifier else { return nil }
        #if DEBUG
        if isPreview && !usesLivePreviewData, let badges = previewBadges { return badges[bundleIdentifier] }
        #endif
        return dockBadgeMonitor.badges[bundleIdentifier]
    }

    @ViewBuilder private func itemViews(_ pass: DockPass, horizontal: Bool, size: CGFloat) -> some View {
        let settings = pass.settings
        let model = pass.model
        let visibleSeparators = DockSeparatorPolicy.visibleSeparatorIDs(model.entries)
        let collapsed = isPreview ? DockSeparatorPolicy.previewCollapsedEntryIDs(model.entries) : []
        let separator = DockDesign.DockChrome.separator(accessibilityStyle.contrast)
        ForEach(model.positionedEntries(settings: settings, scale: size).filter { !collapsed.contains($0.entry.id) },
                id: \.visualID) { positioned in
            let entry = positioned.entry
            switch entry {
            case .item(let item, let pinned):
                if item.type == .spacer {
                    // An invisible gap: it keeps its length, drag and drop target, and label.
                    let spacer = Color.clear
                        .frame(width: horizontal ? entry.length(settings: settings, scale: size) : 42 * size,
                               height: horizontal ? 42 * size : entry.length(settings: settings, scale: size))
                        .contentShape(Rectangle())
                        .accessibilityElement()
                        .accessibilityLabel(item.displayName)
                    if isPreview { spacer.allowsHitTesting(false) }
                    else { spacer
                        .draggable(DockDragPayload(profileID: pass.profile.id, itemIDs: [item.id]))
                        .dropDestination(for: DockDragPayload.self) { values, _ in handleTypedDrop(values, before: item.id) }
                    }
                } else {
                    itemView(item, profile: pass.profile, settings: settings, horizontal: horizontal, size: size,
                             pinned: pinned, center: positioned.center,
                             isRunning: DockTileRunningState.isRunning(item, pinned: pinned, isRecent: pass.recentIDs.contains(item.id),
                                                                       runningPinnedIDs: pass.runningPinnedIDs,
                                                                       runningBundleIdentifiers: pass.runningBundleIdentifiers))
                        .matchedGeometryEffect(id: positioned.visualID, in: profileTransformation)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            case .insertion:
                // The line shows only when content follows; the grip and drop target always exist.
                let showsLine = visibleSeparators.contains(entry.id)
                if isPreview {
                    RoundedRectangle(cornerRadius: 1).fill(showsLine ? separator : Color.clear)
                        .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                        .frame(width: horizontal ? 14 * size : 42 * size, height: horizontal ? 42 * size : 14 * size)
                        .help("Dock separator")
                        .accessibilityLabel("Dock separator")
                } else {
                    // The grip names itself and its resize help; drops here land at the end of the pinned items.
                    resizeGrip(horizontal: horizontal, showsLine: showsLine)
                        .contentShape(Rectangle())
                        .dropDestination(for: DockDropValue.self) { values, _ in
                            let items = values.compactMap { if case .items(let payload) = $0 { payload } else { nil } }
                            let urls = values.compactMap { if case .url(let url) = $0 { url } else { nil } }
                            let moved = !items.isEmpty && handleTypedDrop(items, before: nil)
                            let added = !urls.isEmpty && handleExternalDrop(urls)
                            return moved || added
                        }
                }
            case .boundary(let kind):
                RoundedRectangle(cornerRadius: 1).fill(visibleSeparators.contains(entry.id) ? separator : Color.clear)
                    .frame(width: horizontal ? 1 : 30, height: horizontal ? 30 : 1)
                    .padding(.horizontal, horizontal ? 2 * size : 0)
                    .padding(.vertical, horizontal ? 0 : 2 * size)
                    .help(Self.boundaryHelp(kind))
                    .dropDestination(for: DockDragPayload.self) { values, _ in
                        kind == .running && handleTypedDrop(values, before: nil, unpin: true)
                    }
            case .window(let window):
                WindowDockTile(window: window, size: 48 * size, preview: windowMonitor.preview(for: window)) {
                    switchProfileMenu(settings: settings)
                }
                .scaleEffect(magnification(center: positioned.center, isWidget: false, settings: settings),
                             anchor: Self.unitPoint(facing: settings.customDockPosition))
            }
        }
    }

    private static func boundaryHelp(_ kind: DockBoundaryKind) -> String {
        switch kind {
        case .running: "Drop a pinned app here to unpin it"
        case .recent: "Recent apps"
        case .windows: "Minimized windows"
        }
    }

    @ViewBuilder private func itemView(_ item: DockItem, profile: DockProfile, settings: AppSettings, horizontal: Bool,
                                       size: CGFloat, pinned: Bool, center: CGFloat = 0, isRunning: Bool = false) -> some View {
        let tileWidth = DockSurfaceMetrics.itemLength(item, settings: settings, scale: size)
        let edgeAnchor = Self.unitPoint(facing: settings.customDockPosition)
        let isMissing = missingTargetIDs.contains(item.id)
        let tileBadge = self.badge(for: item)
        let tile = Button {
            guard !isPreview else { return }
            if item.type == .widget {
                popouts.toggle(item.id)
            } else if item.type == .folder {
                // A long press already opened the folder's popout; this release is not a click.
                if longPressTriggeredItemID == item.id {
                    longPressTriggeredItemID = nil
                    return
                }
                AppLauncher.open(item)
            }
            else {
                let minimizesFocusedApp = settings.clickFocusedAppToMinimize
                Task { @MainActor in
                    if minimizesFocusedApp, let identity = AppLauncher.runningIdentity(for: item),
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
            // PX-2: hover a running app for its windows. Hit-test transparent; opt-in.
            .background {
                if WindowPreviewEligibility.showsRegion(itemType: item.type, isRunning: isRunning, isPreview: isPreview,
                                                        popoutOpen: popouts.anchorID != nil,
                                                        enabled: store.state.settings.showWindowPreviewsOnHover) {
                    DockWindowPreviewHoverRegion(key: item.id.uuidString, item: item, position: settings.customDockPosition,
                        colorScheme: DockColorSchemePolicy.scheme(theme: settings.customDockTheme, material: settings.customDockMaterial,
                                                                  system: systemAppearance.scheme),
                        animationsEnabled: settings.dockAnimationsEnabled)
                }
            }
            // Popout anchors carry a glass identity so a popout can morph from its module (macOS 26).
            .modifier(DockPopoutGlassAnchor(id: [.widget, .folder].contains(item.type) ? item.id.uuidString : nil,
                                            namespace: popoutGlass))
            .background(popouts.tabIDs.contains(item.id) || dropTargetedItemID == item.id ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 13 * size))
            // Pressed/active while its popout is open; render-only, so hit areas are unchanged.
            .modifier(DockPopoutAnchorState(isActive: isActivePopoutAnchor(item)))
            .overlay(alignment: .bottomTrailing) {
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11 * size, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(2 * size)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let tileBadge {
                    // Side Docks keep the badge inside the one-tile-wide column (D4).
                    let offset = DockBadgePlacement.offset(position: settings.customDockPosition, scale: size)
                    DockBadgeView(text: tileBadge, scale: size)
                        .offset(x: offset.width, y: offset.height)
                        // Read as part of the tile's value instead.
                        .accessibilityHidden(true)
                }
            }
            .help(isMissing ? "\(item.displayName) · Saved location unavailable" : item.displayName)
        }
        .buttonStyle(.plain)
        .modifier(DockTileAccessibilityModifier(item: item,
                                                value: DockTileAccessibility.value(isRunning: isRunning, isMissing: isMissing, badge: tileBadge),
                                                isSelected: isActivePopoutAnchor(item)))
        .accessibilityHint(isMissing ? "Choose Locate… from its menu to find it." : "")
        .scaleEffect(magnification(center: center, isWidget: item.type == .widget, settings: settings), anchor: edgeAnchor)
        .scaleEffect(DockMotionPolicy.settleScale(isSettling: settlingItemIDs.contains(item.id), reduceMotion: reducesMotion),
                     anchor: edgeAnchor)
        // After magnification: the dot stays at the screen-edge side while the icon grows.
        .overlay(alignment: Self.alignment(facing: settings.customDockPosition)) {
            // Inside the tile's 3 pt inset and the icon canvas margin: clear of the artwork and
            // never clipped by the scroll viewport.
            if isRunning { DockRunningIndicator(scale: size) }
        }
        .zIndex(hoveredItemID == item.id ? 2 : 0)
        .onHover { isHovered in
            guard DockMagnificationSupport.isActive(settings), !reducesMotion else {
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
        .animation(DockMotionPolicy.hoverAnimation(reduceMotion: reducesMotion, animationsEnabled: settings.dockAnimationsEnabled),
                   value: hoverPosition == nil)
        // Like the macOS Dock: the item's own actions first, app-wide choices last.
        .contextMenu {
            if item.type == .widget {
                Button("Configure Widget…") { popouts.open(item.id) }
                if pinned, settings.customDockPosition == .bottom {
                    Menu("Widget Layout") {
                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { option in
                            Button(option.title) {
                                store.updateWidgetConfiguration(itemID: item.id, in: profile.id) { $0.widgetLayout = option.layout }
                            }
                        }
                    }
                }
                // The system Trash is not one of this Dock's items, so it cannot be duplicated.
                if pinned {
                    Button("Duplicate Widget", systemImage: "plus.square.on.square") {
                        _ = store.duplicateWidget(item.id, in: profile.id)
                    }
                }
            } else if item.type == .folder {
                Button("Browse Contents") { popouts.open(item.id) }
                Button("Open in Finder") { AppLauncher.open(item) }
                Divider()
                Button("Customize Folder…", systemImage: "folder.badge.gearshape") { editFolderName(item, profileID: profile.id) }
                Menu("Icon Color") {
                    ForEach(DockProfileColor.allCases) { color in
                        Toggle(color.title, isOn: Binding(
                            get: { item.folderIconColor == color },
                            set: { isOn in if isOn { store.updateItem(item.id, in: profile.id) { $0.folderIconColor = color } } }
                        ))
                    }
                }
                Button("Set Letter…") { editFolderLetter(item, profileID: profile.id) }
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
                    Toggle("Site Icon or Default", isOn: Binding(
                        get: { item.linkIcon == nil },
                        set: { isOn in if isOn { store.updateItem(item.id, in: profile.id) { $0.linkIcon = nil } } }
                    ))
                    ForEach(DockLinkIcon.allCases) { icon in
                        Toggle(isOn: Binding(
                            get: { item.linkIcon == icon },
                            set: { isOn in if isOn { store.updateItem(item.id, in: profile.id) { $0.linkIcon = icon } } }
                        )) {
                            Label(icon.title, systemImage: icon.rawValue)
                        }
                    }
                }
                Button(item.linkFaviconData == nil ? "Fetch Site Icon" : "Refresh Site Icon", systemImage: "globe") { fetchLinkIcon(item) }
                if item.linkFaviconData != nil {
                    Button("Remove Site Icon", role: .destructive) {
                        store.updateItem(item.id, in: profile.id) { $0.linkFaviconData = nil }
                    }
                }
            } else if item.type == .file, let fileURL = item.url {
                Button("Open") { AppLauncher.open(item) }
                Button("Show in Finder") {
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
            Divider()
            if pinned, [.application, .file, .folder].contains(item.type) {
                Button("Locate…", systemImage: "folder.badge.questionmark") {
                    guard let repaired = AppLauncher.chooseReplacement(for: item) else { return }
                    store.updateItem(item.id, in: profile.id) { $0 = repaired }
                }
            }
            if pinned {
                Button("Remove from Dock", role: .destructive) { store.removeItem(item.id, from: profile.id) }
            } else {
                Button("Keep in Dock") { store.add(item.withFreshIdentity(), to: profile.id) }
            }
            Divider()
            switchProfileMenu(settings: settings)
            Button("Settings…", systemImage: "gearshape") { openSettings(.dock) }
        }
        // Only the tile whose popover is showing may dismiss it: after its tab closes, the anchor
        // moves to another tile and this tile's popover reports closing.
        .popover(isPresented: Binding(get: { popouts.anchorID == item.id },
                                      set: { if !$0, popouts.anchorID == item.id { popouts.dismiss() } }),
                 arrowEdge: Self.edge(facing: settings.customDockPosition)) {
            if let activeItem = popoutItem(for: popouts.activeID) {
                let tabs = openPopoutTabs
                VStack(alignment: .leading, spacing: 0) {
                    if tabs.count > 1 {
                        popoutTabBar(tabs)
                            .padding(.horizontal, WidgetPopoutMetrics.padding)
                            .padding(.top, WidgetPopoutMetrics.padding)
                    }
                    DockScrollView(.vertical) {
                        if activeItem.type == .widget {
                            // The shell carries its own insets and draws no card of its own.
                            WidgetPopout(store: store, item: activeItem, profileID: profile.id)
                                .frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
                                // PX-7: lets a popout open another widget's popout here as a tab.
                                .environment(\.widgetPopoutOpener, WidgetPopoutOpener(open: { popouts.open($0) }))
                        } else if activeItem.type == .folder, let folderURL = activeItem.url {
                            FolderContentsPopout(folderURL: folderURL, folderName: activeItem.displayName) { popouts.dismiss() }
                                .padding(8)
                        }
                    }
                }
                // The popover window opens natively; its content springs in from the Dock side.
                .modifier(DockPopoutAppearEffect(anchor: edgeAnchor))
                // One surface: the popover's own material (opaque under Reduce Transparency).
                .modifier(WidgetPopoverSurface())
                // The same scheme as the Dock, including the Midnight material's dark appearance.
                .preferredColorScheme(DockColorSchemePolicy.scheme(theme: settings.customDockTheme, material: settings.customDockMaterial,
                                                                   system: systemAppearance.scheme))
                .frame(minWidth: 250, minHeight: 150, maxHeight: popoutMaxHeight(displayID: settings.customDockDisplayID),
                       alignment: .topLeading)
                .id(activeItem.id)
            }
        }
        .id(item.id.uuidString)

        // One modifier chain per tile kind, whatever the popout state, so opening or closing a popout
        // never rebuilds the tiles. The drop handlers reject drops while a popout is open.
        if isPreview {
            tile.allowsHitTesting(false).accessibilityHidden(true)
        } else if pinned {
            if DockDropOpenPolicy.opensDroppedContent(on: item) {
                // Files dropped ON an app tile open with that app; reordering is unchanged.
                tile
                    .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                    .dropDestination(for: DockDropValue.self, action: { values, _ in
                        handleApplicationTileDrop(values, on: item, before: item.id, unpin: false)
                    }, isTargeted: { setDropTarget($0, for: item) })
            } else {
                tile
                    .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                    .dropDestination(for: DockDragPayload.self) { values, _ in
                        handleTypedDrop(values, before: item.id)
                    }
            }
        } else if item.type == .application {
            tile
                .draggable(DockDragPayload(profileID: profile.id, itemIDs: [item.id]))
                .dropDestination(for: DockDropValue.self, action: { values, _ in
                    handleApplicationTileDrop(values, on: item, before: nil, unpin: true)
                }, isTargeted: { setDropTarget($0, for: item) })
        } else {
            tile
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

    private func editFolderName(_ item: DockItem, profileID: UUID) {
        guard let name = DockItemPrompts.folderName(for: item) else { return }
        store.updateItem(item.id, in: profileID) { $0.folderCustomName = FolderCustomizationPolicy.name(name) }
    }

    private func editFolderLetter(_ item: DockItem, profileID: UUID) {
        guard let letter = DockItemPrompts.folderLetter(for: item) else { return }
        store.updateItem(item.id, in: profileID) { $0.folderIconLetter = FolderCustomizationPolicy.letter(letter) }
    }

    private static func unitPoint(facing position: DockPosition) -> UnitPoint {
        switch position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private static func alignment(facing position: DockPosition) -> Alignment {
        switch position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private static func edge(facing position: DockPosition) -> Edge {
        switch position {
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

    /// No magnification on macOS 13, where the scroll view would clip the enlarged tiles.
    private func magnification(center: CGFloat, isWidget: Bool, settings: AppSettings) -> CGFloat {
        guard !isWidget, !isPreview, popouts.anchorID == nil else { return 1 }
        return DockContinuousMagnification.scale(center: center, pointer: hoverPosition,
            radius: 150 * DockSurfaceMetrics.clampedScale(settings.customDockSize), isWidget: isWidget,
            enabled: DockMagnificationSupport.isActive(settings), reduceMotion: reducesMotion)
    }

    private func handleTypedDrop(_ values: [DockDragPayload], before targetID: UUID?, unpin: Bool = false) -> Bool {
        guard !isPreview, popouts.anchorID == nil, let payload = values.first else { return false }
        let profile = self.profile
        return apply(DockDropRouter.typedDrop(payload, profile: profile, runtimeApps: draggableRuntimeApps(profile: profile),
                                              before: targetID, unpin: unpin),
                     in: profile.id)
    }

    private func apply(_ action: DockDropAction, in profileID: UUID) -> Bool {
        switch action {
        case .rejected:
            return false
        case .pin(let items, before: let targetID):
            let pinned = items.compactMap { store.insert($0.withFreshIdentity(), before: targetID, in: profileID) }
            settle(Set(pinned))
            return true
        case .move(let itemIDs, before: let targetID):
            store.moveItems(itemIDs, before: targetID, in: profileID)
            settle(itemIDs)
            return true
        case .unpin(let itemIDs):
            store.removeItems(itemIDs, from: profileID)
            return true
        }
    }

    /// Running and recent unpinned apps: both can be dragged into the pinned items.
    private func draggableRuntimeApps(profile: DockProfile) -> [DockItem] {
        let matches = runningMatches(profile: profile)
        return matches.unpinnedRuntime
            + recentApplicationItems(profile: profile, settings: store.effectiveSettings(for: profile), matches: matches)
    }

    /// A drop ON an application tile: Dock items reorder as before; Finder files or addresses open
    /// with that app. Anything else is rejected.
    private func handleApplicationTileDrop(_ values: [DockDropValue], on item: DockItem, before targetID: UUID?, unpin: Bool) -> Bool {
        let payloads = values.compactMap { if case .items(let payload) = $0 { payload } else { nil } }
        if !payloads.isEmpty { return handleTypedDrop(payloads, before: targetID, unpin: unpin) }
        let urls = values.compactMap { if case .url(let url) = $0 { url } else { nil } }
        guard !isPreview, popouts.anchorID == nil, DockDropOpenPolicy.opensDroppedContent(on: item) else { return false }
        let openable = DockDropOpenPolicy.openableURLs(urls) { FileManager.default.fileExists(atPath: $0.path) }
        guard !openable.isEmpty else { return false }
        AppLauncher.open(openable, with: item)
        return true
    }

    /// Highlights an application tile only for Finder or address drags, not for Dock reordering,
    /// and never while a popout is open (drops are rejected then).
    private func setDropTarget(_ isTargeted: Bool, for item: DockItem) {
        if isTargeted, popouts.anchorID == nil {
            let types = NSPasteboard(name: .drag).types?.map(\.rawValue) ?? []
            dropTargetedItemID = DockDropOpenPolicy.carriesOpenableContent(typeIdentifiers: types) ? item.id : nil
        } else if dropTargetedItemID == item.id {
            dropTargetedItemID = nil
        }
    }

    private func handleExternalDrop(_ urls: [URL]) -> Bool {
        guard !isPreview, popouts.anchorID == nil else { return false }
        let items = DockDropRouter.externalItems(
            for: urls,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            isDirectory: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        guard !items.isEmpty else { return false }
        let profileID = profile.id
        for item in items { store.add(item, to: profileID) }
        return true
    }

    private var openPopoutTabs: [DockItem] {
        popouts.tabIDs.compactMap { popoutItem(for: $0) }
    }

    /// Native segmented tabs: the selected tab is a real selection for VoiceOver, the keyboard and
    /// Increase Contrast. One close button closes the tab that is showing.
    private func popoutTabBar(_ tabs: [DockItem]) -> some View {
        HStack(spacing: DockDesign.Space.xxs) {
            DockScrollView(.horizontal) {
                Picker("Open Popouts", selection: Binding(
                    get: { popouts.activeID },
                    set: { if let itemID = $0 { popouts.select(itemID) } }
                )) {
                    ForEach(tabs) { tab in
                        Text(tab.displayName).lineLimit(1).tag(Optional(tab.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .scrollIndicators(.hidden)
            if let active = tabs.first(where: { $0.id == popouts.activeID }) {
                Button {
                    popouts.close(active.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close \(active.displayName)")
                .accessibilityLabel("Close \(active.displayName)")
            }
        }
        .frame(height: 28)
    }

    private func popoutItem(for itemID: UUID?) -> DockItem? {
        guard let itemID else { return nil }
        if let item = visibleProfileItems.first(where: { $0.id == itemID }) { return item }
        return systemTrashItem.id == itemID ? systemTrashItem : nil
    }

    private func reconcilePopouts() {
        let profile = self.profile
        var validIDs = Set(visibleProfileItems.map(\.id))
        if CustomDockVisibilityPolicy.showsSystemTrash(
            isEnabled: store.effectiveSettings(for: profile).showTrash,
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
                runningSources: runningMediaSources)
        }
    }
}

/// What VoiceOver hears for a tile. Widget faces name themselves and read their own value; folder
/// and link icons (a default folder, a fetched favicon) carry no description, so they get the
/// item's name. Every tile adds its running, missing and badge state, and the tile under an open
/// popout is selected.
private struct DockTileAccessibilityModifier: ViewModifier {
    var item: DockItem
    var value: String
    var isSelected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        switch item.type {
        case .widget:
            content.accessibilityAddTraits(traits)
        case .folder, .link:
            content.accessibilityLabel(item.displayName).accessibilityValue(value).accessibilityAddTraits(traits)
        case .application, .file, .spacer:
            content.accessibilityValue(value).accessibilityAddTraits(traits)
        }
    }
}

/// A minimized window in the Dock's windows section (only minimized windows are listed there).
private struct WindowDockTile<SwitchProfileMenu: View>: View {
    var window: DockWindowDescriptor
    var size: CGFloat
    var preview: NSImage?
    @ViewBuilder var switchProfileMenu: SwitchProfileMenu
    @DockAccessibilityStyle() private var accessibility

    /// The icon of the app that owns the window, from the bundle observed with it: no process lookup
    /// on each render (icons are cached by `AppLauncher`).
    private var icon: NSImage {
        if let bundleURL = window.applicationIdentity?.bundleURL {
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
                        .background(DockDesign.selection, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(DockDesign.Outline.color(accessibility.contrast),
                                    lineWidth: DockDesign.Outline.controlWidth(accessibility.contrast)))
                } else {
                    Image(nsImage: icon).resizable().scaledToFit()
                }
            }
                .frame(width: size, height: size)
                .padding(3)
        }
        .buttonStyle(.plain)
        .help("\(window.title) · \(window.applicationName)")
        .accessibilityLabel("Minimized window: \(window.title), \(window.applicationName)")
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

/// Glass container and concentric module radius around the Dock's item stack. The stack,
/// its laziness, hover coordinate space and scrolling are unchanged.
private struct DockItemStackPresentation: ViewModifier {
    var glassGroup: Bool
    var moduleRadius: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if glassGroup {
            // Spacing 0: modules blend only when they touch (morphs), never at rest.
            DockGlassGroup(spacing: DockGlassComposition.moduleSpacing) { content.environment(\.dockModuleRadius, moduleRadius) }
        } else {
            content.environment(\.dockModuleRadius, moduleRadius)
        }
    }
}

/// Popout content opens from 96% with a fade on `Motion.appear`; instant under Reduce Motion.
/// The popover itself is an NSPopover window, so a true glass morph from the module is not
/// possible; `progress` pins a frame (0…1) for render exports.
struct DockPopoutAppearEffect: ViewModifier {
    var anchor: UnitPoint
    var progress: Double?
    @State private var appeared = false
    @DockAccessibilityStyle() private var accessibility

    init(anchor: UnitPoint, progress: Double? = nil) {
        self.anchor = anchor
        self.progress = progress
    }

    func body(content: Content) -> some View {
        let reduceMotion = accessibility.reduceMotion
        let frame = progress ?? (appeared ? 1 : 0)
        content
            .scaleEffect(DockMotionPolicy.popoutContentScale(progress: frame, reduceMotion: reduceMotion), anchor: anchor)
            .opacity(DockMotionPolicy.popoutContentOpacity(progress: frame, reduceMotion: reduceMotion))
            .onAppear {
                guard progress == nil, !appeared else { return }
                DockDesign.Motion.perform(DockDesign.Motion.appear, reduceMotion: reduceMotion) { appeared = true }
            }
    }
}

/// The module under an open popout reads as pressed: a slight scale-down and brightening on the
/// hover spring. Reduce Motion keeps only the (instant) brightening.
struct DockPopoutAnchorState: ViewModifier {
    var isActive: Bool
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let reduceMotion = accessibility.reduceMotion
        content
            .scaleEffect(DockMotionPolicy.anchorScale(isActive: isActive, reduceMotion: reduceMotion))
            .brightness(DockMotionPolicy.anchorBrightness(isActive: isActive, dark: scheme == .dark))
            .animation(DockMotionPolicy.anchorAnimation(reduceMotion: reduceMotion), value: isActive)
    }
}

/// Wiring for popout morphs: the anchor's glass gets a stable identity in the Dock namespace.
private struct DockPopoutGlassAnchor: ViewModifier {
    var id: String?
    var namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

/// A small round dot for a running app; no capsule or box behind it.
struct DockRunningIndicator: View {
    var scale: CGFloat
    @DockAccessibilityStyle() private var accessibility
    var body: some View {
        let increased = accessibility.contrast == .increased
        let diameter = (increased ? 5 : 4) * scale
        Circle()
            .fill(Color.primary.opacity(increased ? 1 : 0.7))
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A clean red capsule with white semibold digits. Increase Contrast adds a white edge.
struct DockBadgeView: View {
    var text: String
    var scale: CGFloat
    @DockAccessibilityStyle() private var accessibility
    var body: some View {
        Text(text)
            .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5 * scale)
            .frame(minWidth: 16 * scale, minHeight: 16 * scale)
            .background(Capsule().fill(Color(nsColor: .systemRed)))
            .overlay {
                if accessibility.contrast == .increased { Capsule().dockInnerEdge(.white, lineWidth: 1) }
            }
            .accessibilityLabel("Notification badge \(text)")
    }
}

#if DEBUG
private struct DockPreviewRunningBundleIdentifiersKey: EnvironmentKey { static let defaultValue: Set<String>? = nil }
private struct DockPreviewBadgesKey: EnvironmentKey { static let defaultValue: [String: String]? = nil }
private struct DockPreviewActivePopoutAnchorKey: EnvironmentKey { static let defaultValue: UUID? = nil }
extension EnvironmentValues {
    /// Render-only: running apps for sample previews, which never read the live process list.
    var dockPreviewRunningBundleIdentifiers: Set<String>? {
        get { self[DockPreviewRunningBundleIdentifiersKey.self] } set { self[DockPreviewRunningBundleIdentifiersKey.self] = newValue }
    }
    /// Render-only: badge text by bundle identifier for sample previews.
    var dockPreviewBadges: [String: String]? {
        get { self[DockPreviewBadgesKey.self] } set { self[DockPreviewBadgesKey.self] = newValue }
    }
    /// Render-only: the item drawn in its open-popout (active anchor) state in sample previews.
    var dockPreviewActivePopoutAnchor: UUID? {
        get { self[DockPreviewActivePopoutAnchorKey.self] } set { self[DockPreviewActivePopoutAnchorKey.self] = newValue }
    }
}
#endif
