import SwiftUI

/// Fits short widget editors to their content and keeps longer ones within the
/// workspace, with native scrolling and an always reachable dismiss control.
struct WidgetConfigurationSheet: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var maximumHeight: CGFloat = 640
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 360
    @State private var showsAppearance = false
    @State private var editorDemand = RefreshDemandHolder(kind: .editor)

    private var currentItem: DockItem {
        store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id } ?? item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DockDesign.Space.large) {
            HStack {
                WidgetEmblem(kind: currentItem.widgetKind ?? currentItem.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem.displayName).font(.system(size: 17, weight: .semibold))
                    Text((WidgetRegistry.all.first { $0.name == currentItem.widgetKind }?.category.rawValue ?? "Dock") + " widget").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(DockButtonStyle(icon: true))
                    .help("Close widget settings").accessibilityLabel("Close widget settings")
            }
            WidgetAppearanceControls(store: store, item: currentItem, profileID: profileID, part: .preview)
            DockScrollView {
                VStack(alignment: .leading, spacing: DockDesign.Space.large) {
                    // Task and setup content first; appearance is optional and follows it.
                    WidgetPopout(store: store, item: currentItem, profileID: profileID, showsCustomize: false, showsHeader: false)
                    Divider()
                    DisclosureGroup(isExpanded: $showsAppearance) {
                        WidgetAppearanceControls(store: store, item: currentItem, profileID: profileID, part: .options).padding(.top, 10)
                    } label: {
                        Text("Appearance").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }.accessibilityLabel("Appearance, layout and icon")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: WidgetConfigurationHeightKey.self, value: geometry.size.height)
                })
            }
            .frame(height: min(contentHeight, max(200, maximumHeight - 190)))
            .onPreferenceChange(WidgetConfigurationHeightKey.self) { height in
                if height > 0 { contentHeight = height }
            }
        }
        .padding(DockDesign.Space.section)
        .frame(width: 488)
        .background(WidgetDesign.surface)
        .buttonStyle(DockButtonStyle())
        .textFieldStyle(DockTextFieldStyle())
        .onExitCommand { dismiss() }
        // Live previews keep refreshing while the Dock is hidden; the token is released when the editor goes away.
        .onAppear { editorDemand.begin() }
        .onDisappear { editorDemand.end() }
    }
}

/// Holds one typed refresh-demand token for exactly as long as a visible consumer asks for it.
@MainActor
final class RefreshDemandHolder {
    private let kind: RefreshDemandKind
    private let scheduler: RefreshScheduler
    private var token: RefreshDemandToken?
    var isHolding: Bool { token != nil }

    init(kind: RefreshDemandKind, scheduler: RefreshScheduler = .shared) {
        self.kind = kind; self.scheduler = scheduler
    }

    func begin() { scheduler.setDemand(&token, kind: kind, active: true) }
    func end() { scheduler.setDemand(&token, kind: kind, active: false) }
}

private struct WidgetConfigurationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
