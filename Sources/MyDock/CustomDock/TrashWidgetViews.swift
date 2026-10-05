import SwiftUI

struct TrashWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TrashCompactWidgetView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TrashPopoutWidgetView())
    }
}

#if DEBUG
/// Render-QA seam: a fixed Trash reading instead of the isolated-session status, set only by DEBUG exports.
@MainActor
enum TrashQAFixture {
    static var override: (count: Int, errorMessage: String?)?
}
#endif

/// Pure Trash presentation: glyph, short label and the "full" state that faces colour.
struct TrashFacePresentation: Equatable {
    var symbol: String
    var label: String
    var isFull: Bool
    var isUnavailable: Bool

    init(count: Int, errorMessage: String?) {
        isUnavailable = errorMessage != nil
        isFull = errorMessage == nil && count > 0
        symbol = isUnavailable ? "exclamationmark.triangle" : isFull ? "trash.fill" : "trash"
        label = isUnavailable ? "Unavailable" : count == 0 ? "Empty" : count == 1 ? "1 item" : "\(count) items"
    }

    /// The popout hero: the count (or "Empty", "Unavailable") as the one large value.
    static func heroValue(count: Int, errorMessage: String?) -> String {
        errorMessage != nil ? "Unavailable" : count == 0 ? "Empty" : "\(count)"
    }

    /// The hero's one secondary line: only the unit. Where the count comes from is said once, by the
    /// `TrashCopy.countScope` footer, so the hero never repeats it.
    static func heroCaption(count: Int, errorMessage: String?) -> String? {
        guard errorMessage == nil, count > 0 else { return nil }
        return count == 1 ? "item" : "items"
    }
}

/// The Trash module: a Control Center toggle glyph, filled while the home Trash has items;
/// wider layouts add one short line ("12 items", "Empty").
struct TrashDockFace: View {
    var count: Int
    var errorMessage: String?
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetShowsLabel) private var showsLabel
    private var state: TrashFacePresentation { TrashFacePresentation(count: count, errorMessage: errorMessage) }
    private var showsName: Bool { layout != .icon && !WidgetModuleMetrics.isNarrow(width) && showsLabel }
    var body: some View {
        VStack(spacing: 2) {
            WidgetToggleGlyph(kind: "Trash", symbol: state.symbol, active: state.isFull, diameter: showsName ? 30 : 36)
            if showsName {
                Text(state.label).font(DockDesign.Module.label).monospacedDigit()
                    .foregroundStyle(state.isUnavailable ? .secondary : .primary)
                    .lineLimit(1).minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
        }
        .moduleInsets()
    }
}

private struct TrashCompactWidgetView: View {
    @ObservedObject private var status = TrashStatus.shared
    @Environment(\.dockWidgetContentWidth) private var width

    private var reading: (count: Int, errorMessage: String?) {
        #if DEBUG
        if let fixture = TrashQAFixture.override { return fixture }
        #endif
        return (status.itemCount, status.errorMessage)
    }

    var body: some View {
        let reading = reading
        TrashDockFace(count: reading.count, errorMessage: reading.errorMessage)
            .frame(width: width, height: 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trash")
            .accessibilityValue(reading.errorMessage ?? (reading.count == 0 ? "Empty" : "\(reading.count) items in home Trash"))
            .help(reading.errorMessage ?? (reading.count == 0 ? "Home Trash is empty" : TrashCopy.countLabel(reading.count)))
    }
}

private struct TrashPopoutWidgetView: View {
    @ObservedObject private var status = TrashStatus.shared
    @State private var confirmingEmpty = false
    @State private var actionError: String?

    private var reading: (count: Int, errorMessage: String?) {
        #if DEBUG
        if let fixture = TrashQAFixture.override { return fixture }
        #endif
        return (status.itemCount, status.errorMessage)
    }

    var body: some View {
        let reading = reading
        let state = TrashFacePresentation(count: reading.count, errorMessage: reading.errorMessage)
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            // The glyph is the hero's decoration: the settings sheet hides both together.
            WidgetPopoutHeroGroup {
                VStack(spacing: 4) {
                    WidgetToggleGlyph(kind: "Trash", symbol: state.symbol, active: state.isFull, diameter: 48)
                    WidgetPopoutHero(value: TrashFacePresentation.heroValue(count: reading.count, errorMessage: reading.errorMessage),
                                     caption: TrashFacePresentation.heroCaption(count: reading.count, errorMessage: reading.errorMessage),
                                     valueColor: state.isUnavailable ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity)
            }
            if let errorMessage = reading.errorMessage {
                WidgetPopoutCaption(errorMessage, color: .orange)
            }
            GroupedSection(footer: TrashCopy.countScope, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Open Trash", role: .button, action: TrashActions.openTrash)
                GroupedRow("Empty Trash…", role: .destructive) { confirmingEmpty = true }
                    .help(TrashCopy.emptyHelp)
                    .disabled(reading.count == 0 || reading.errorMessage != nil)
            }
        }
        .task { status.refresh() }
        .confirmationDialog(TrashCopy.emptyConfirmationTitle, isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button(TrashCopy.emptyButton, role: .destructive, action: emptyTrash)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(TrashCopy.emptyConfirmationMessage)
        }
        .alert("Trash", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func emptyTrash() {
        Task { @MainActor in
            do { try await TrashActions.emptyTrash(); status.refresh() }
            catch { actionError = error.localizedDescription }
        }
    }
}
