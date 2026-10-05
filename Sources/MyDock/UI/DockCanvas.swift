import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The editor uses the same widget content and metrics as the live Dock, while
/// intercepting clicks for editing rather than launching apps or running actions.
struct DockCanvas: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    let profile: DockProfile
    @Binding var selection: Set<UUID>
    var cursor: UUID? = nil
    private struct ItemFocus: Hashable {
        let itemID: UUID
        let requestID: UUID
    }
    @FocusState private var focusedItem: ItemFocus?
    @State private var focusRequestID = UUID()
    let select: (UUID, Bool, Bool) -> Void
    let move: (Set<UUID>, UUID?) -> Void
    let configure: (DockItem) -> Void
    let remove: (DockItem) -> Void
    let replace: (DockItem) -> Void
    let duplicate: (DockItem) -> Void
    let addURLs: ([URL], UUID?) -> Void
    @Namespace private var transformation
    @DockAccessibilityStyle() private var accessibility
    @State private var insertion: UUID?
    /// Items just moved (keyboard, accessibility action or drop); they settle on `Motion.morph`.
    @State private var settlingItemIDs: Set<UUID> = []
    @State private var settledOrder: [UUID] = []
    @State private var atEnd = false
    @State private var liftedItems: Set<UUID> = []
    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    private var scale: CGFloat { CGFloat(settings.customDockSize) }

    private var contentLength: CGFloat {
        profile.items.reduce(0) { $0 + DockSurfaceMetrics.itemLength($1, settings: settings, scale: scale) }
            + CGFloat(profile.items.count) * CGFloat(settings.customDockItemSpacing) * scale + 24 * scale + 48 + 24
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CGFloat(settings.customDockItemSpacing) * scale) {
                ForEach(DockVisualIdentity.items(profile.items)) { visual in
                    let item = visual.item
                    tile(item)
                        .scaleEffect(DockMotionPolicy.settleScale(isSettling: settlingItemIDs.contains(item.id),
                                                                  reduceMotion: reduceMotion))
                        .opacity(liftedItems.contains(item.id) ? 0.35 : 1)
                        .matchedGeometryEffect(id: visual.id, in: transformation)
                        .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity), removal: .opacity))
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: DockCanvasItemFrames.self,
                                                   value: [item.id: geometry.frame(in: .named("dock-drag-content"))])
                        })
                        .padding(.leading, insertion == item.id ? 12 : 0)
                        .overlay(alignment: .leading) {
                            if insertion == item.id { Capsule().fill(DockDesign.accent).frame(width: 2, height: 40) }
                        }
                }
                Color.primary.opacity(0.001).frame(width: 24, height: 56 * scale).contentShape(Rectangle())
                    .overlay { if atEnd { Capsule().fill(DockDesign.accent).frame(width: 2, height: 40) } }
                    .accessibilityLabel("Drop at end of Dock")
            }
            .padding(12 * scale)
            .coordinateSpace(name: "dock-drag-content")
            .overlayPreferenceValue(DockCanvasItemFrames.self) { frames in
                DockCanvasDragSurface(profileID: profile.id, items: profile.items, frames: frames, selection: selection,
                                      select: select, hover: { target, active in
                                          insertion = active ? target : nil
                                          atEnd = active && target == nil
                                      }, lift: { liftedItems = $0 }, drop: { values, before in handleDrop(values, before: before) })
            }
            .background(DockMaterialSurface(settings: settings, color: (DockProfileColor(rawValue: profile.color) ?? .blue).displayColor))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .environment(\.colorScheme, DockColorSchemePolicy.scheme(theme: settings.customDockTheme, material: settings.customDockMaterial,
                                                                      system: systemAppearance.scheme))
            .padding(24)
            .frame(minWidth: geometry.size.width)
        }
        .overlay(alignment: .bottom) {
            if contentLength > geometry.size.width {
                Text("Scroll to see all items").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        }
        .frame(height: 58 * scale + 8 + 24 * scale + 48)
        .onChange(of: cursor) { id in
            focusedItem = id.map { ItemFocus(itemID: $0, requestID: focusRequestID) }
        }
        .onChange(of: liftedItems) { items in
            // Reordering can replace the native responder behind a SwiftUI tile.
            // A new request also reacquires focus when the cursor itself is unchanged.
            if items.isEmpty {
                focusedItem = nil
                focusRequestID = UUID()
            }
        }
        .task(id: [profile.id, focusRequestID]) {
            // Let SwiftUI register the reordered tile's new focus binding first.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedItem = cursor.map { ItemFocus(itemID: $0, requestID: focusRequestID) }
        }
        // The live Dock's reorder motion: items glide on `Motion.reorder`, then moved items settle.
        .animation(DockMotionPolicy.reorderAnimation(reduceMotion: reduceMotion, animationsEnabled: settings.dockAnimationsEnabled),
                   value: profile.items)
        .animation(DockMotionPolicy.reorderAnimation(reduceMotion: reduceMotion, animationsEnabled: settings.dockAnimationsEnabled),
                   value: insertion)
        .onAppear { settledOrder = profile.items.map(\.id) }
        .onChange(of: profile.items.map(\.id)) { order in
            let moved = DockReorderSettlePolicy.movedItems(from: settledOrder, to: order, selection: selection)
            settledOrder = order
            settle(moved)
        }
        .accessibilityLabel("Dock workspace. Select items to edit, or drag to reorder.")
    }

    private var reduceMotion: Bool { accessibility.reduceMotion }

    /// Moved items dip slightly and settle on `Motion.morph`; nothing moves under Reduce Motion.
    private func settle(_ itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty,
              let animation = DockMotionPolicy.settleAnimation(reduceMotion: reduceMotion,
                                                               animationsEnabled: settings.dockAnimationsEnabled) else { return }
        settlingItemIDs = itemIDs
        DispatchQueue.main.async { withAnimation(animation) { settlingItemIDs = [] } }
    }

    private func handleDrop(_ values: [DockDropValue], before: UUID?) -> Bool {
        var accepted = false
        for value in values {
            if case .items(let payload) = value, payload.profileID == profile.id {
                move(Set(payload.itemIDs), before); accepted = true
            }
        }
        let urls = values.compactMap { value -> URL? in if case .url(let url) = value { return url }; return nil }
        if !urls.isEmpty { addURLs(urls, before); accepted = true }
        insertion = nil
        return accepted
    }

    private func tile(_ item: DockItem) -> some View {
        Button {
            let flags = NSEvent.modifierFlags
            select(item.id, flags.contains(.command), flags.contains(.shift))
        } label: {
            DockCanvasItem(store: store, profileID: profile.id, item: item, settings: settings)
                .scaleEffect(scale)
                .frame(width: max(16, DockSurfaceMetrics.itemLength(item, settings: settings, scale: scale)), height: 58 * scale)
                .padding(.vertical, 4)
                .background(selection.contains(item.id) ? DockDesign.accent.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: DockDesign.Radius.control))
                .overlay(alignment: .bottom) {
                    if selection.contains(item.id) { Capsule().fill(DockDesign.accent).frame(width: 12, height: 2).offset(y: 6) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focusable().focused($focusedItem, equals: ItemFocus(itemID: item.id, requestID: focusRequestID))
            .help(item.displayName + (AppLauncher.isMissingTarget(item) ? " · Saved location missing" : "") + " · Drag to reorder")
            .accessibilityLabel(DockItemAccessibility.label(for: item, missing: AppLauncher.isMissingTarget(item)))
            .accessibilityHint(AppLauncher.isMissingTarget(item) ? "Saved location missing. Use Replace to reconnect this item." : "Select to edit. Drag to reorder.")
            .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
            .accessibilityAction(named: "Configure") { configure(item) }
            .accessibilityAction(named: "Move earlier") {
                if let index = profile.items.firstIndex(where: { $0.id == item.id }), index > 0 { move([item.id], profile.items[index - 1].id) }
            }
            .accessibilityAction(named: "Move later") {
                if let index = profile.items.firstIndex(where: { $0.id == item.id }), index < profile.items.count - 1 {
                    move([item.id], index + 2 < profile.items.count ? profile.items[index + 2].id : nil)
                }
            }
            .accessibilityAction(named: "Move to start") { move([item.id], profile.items.first(where: { $0.id != item.id })?.id) }
            .accessibilityAction(named: "Move to end") { move([item.id], nil) }
            .contextMenu {
                Button("Configure…") { configure(item) }
                if [.application, .file, .folder, .link].contains(item.type) { Button("Replace…") { replace(item) } }
                Button("Duplicate") { duplicate(item) }
                Divider()
                Button("Remove from Dock", role: .destructive) { remove(item) }
            }
    }
}

struct DockCanvasItem: View {
    @ObservedObject var store: ProfileStore
    let profileID: UUID
    let item: DockItem
    let settings: AppSettings
    var body: some View {
        Group {
            switch item.type {
            case .widget:
                WidgetCompactView(store: store, item: item, profileID: profileID,
                                  sampleMode: !store.allowsSystemChanges, presentationSettings: settings)
                    .frame(width: DockSurfaceMetrics.itemLength(item, settings: settings, scale: 1), height: 54)
            case .spacer:
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.25))
                    .frame(width: 2, height: 28).frame(width: item.spacerKind == .small ? 12 : 24, height: 54)
            case .application: DockApplicationIconView(item: item, size: 48)
            case .folder: DockFolderIconView(item: item, size: 48)
            case .file: DockFileThumbnailView(item: item, size: 48)
            case .link: Image(nsImage: AppLauncher.icon(for: item, size: 48)).resizable().scaledToFit().frame(width: 48, height: 48)
            }
        }.overlay(alignment: .bottomTrailing) {
            if AppLauncher.isMissingTarget(item) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

enum DockItemAccessibility {
    static func kindName(_ type: DockItemType) -> String {
        switch type {
        case .application: "Application"
        case .folder: "Folder"
        case .file: "File"
        case .link: "Link"
        case .widget: "Widget"
        case .spacer: "Spacer"
        }
    }

    /// Item name, kind and missing state; the selected trait is added by the tile itself.
    static func label(for item: DockItem, missing: Bool) -> String {
        let name = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = kindName(item.type)
        let base = name.isEmpty || name == kind ? kind : "\(name), \(kind)"
        return missing ? base + ", missing" : base
    }
}
