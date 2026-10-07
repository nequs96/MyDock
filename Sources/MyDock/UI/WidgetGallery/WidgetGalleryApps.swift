import AppKit
import SwiftUI

/// One installed app in the Apps segment's inset list. The whole row adds the app;
/// an app already on the Dock shows a check and cannot be added twice.
struct WidgetGalleryAppRow: View {
    var entry: WidgetGalleryApplicationEntry
    var added: Bool
    var selected: Bool
    var enabled: Bool
    var addGeneration = 0
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                InstalledApplicationIcon(application: entry.application).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.system(size: 13)).lineLimit(1)
                    if !entry.detail.isEmpty {
                        Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                let accessory = WidgetGalleryRowAccessory(added: added)
                if accessory == .added {
                    // A plain check: clearly not the filled plus it replaces.
                    GalleryAddedCheck(generation: addGeneration)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Image(systemName: accessory.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(enabled ? DockDesign.accent : Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(selected ? WidgetGalleryMetrics.highlightFill(scheme) : hovered && !added ? DockDesign.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title + (entry.detail.isEmpty ? "" : ", " + entry.detail) + WidgetGalleryRowAccessory(added: added).labelSuffix)
        .accessibilityHint(added ? "Already in this Dock." : "Adds the app to this Dock.")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .help(entry.application.url.path)
    }
}

/// The trailing mark of an app row. "Add" is the filled accent plus; "Added" is a bare
/// check with no filled circle, so the two never look alike.
enum WidgetGalleryRowAccessory: Equatable {
    case add, added
    init(added: Bool) { self = added ? .added : .add }
    var symbol: String { self == .added ? "checkmark" : "plus.circle.fill" }
    var drawsFilledCircle: Bool { self == .add }
    /// Appended to the row's VoiceOver label.
    var labelSuffix: String { self == .added ? ", Added" : "" }
}

/// The inset grouped container of the app list, lazily stacked for large app folders.
struct WidgetGalleryAppList<Rows: View>: View {
    @ViewBuilder var rows: Rows
    @DockAccessibilityStyle() private var accessibility
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    var body: some View {
        LazyVStack(spacing: 0) { rows }
            .background(DockDesign.Grouped.fill, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(DockDesign.Outline.color(accessibility.contrast),
                                   lineWidth: DockDesign.Outline.controlWidth(accessibility.contrast))
            }
    }
}

struct WidgetGalleryRowSeparator: View {
    @DockAccessibilityStyle() private var accessibility
    var body: some View {
        Rectangle()
            .fill(accessibility.contrast == .increased ? DockDesign.Outline.color(.increased) : DockDesign.Grouped.separator)
            .frame(height: 0.5)
            .padding(.leading, 56)
            .accessibilityHidden(true)
    }
}

struct InstalledApplicationIcon: View {
    var application: InstalledApplication
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.secondary) }
        }.frame(width: 32, height: 32)
            .task(id: application.id) {
                let url = application.url
                let worker = Task.detached(priority: .utility) { InstalledApplicationIconLoader.load(at: url) }
                let data = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                icon = data.flatMap(NSImage.init(data:))
            }
    }
}

#if DEBUG
/// Render-only state for the gallery exports. Release builds never read it.
struct AddLibraryPreviewState {
    var scan: InstalledAppScan?
    var detailFamily: String?
    var detailLayout: WidgetLayout?
    /// Snapshots cannot scroll; the export starts the Widgets content at this section.
    var startSection: WidgetCategory?
    var recentlyAdded: Set<String> = []
    /// Snapshots have no key window; the export draws this tile id as keyboard-focused.
    var focusedTile: String?
}
private struct AddLibraryPreviewStateKey: EnvironmentKey { static let defaultValue: AddLibraryPreviewState? = nil }
extension EnvironmentValues {
    var addLibraryPreview: AddLibraryPreviewState? {
        get { self[AddLibraryPreviewStateKey.self] }
        set { self[AddLibraryPreviewStateKey.self] = newValue }
    }
}
#endif
