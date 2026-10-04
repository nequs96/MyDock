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
                if added {
                    GalleryAddedBadge(generation: addGeneration, size: 20)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(enabled ? DockDesign.accent : Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(selected ? DockDesign.accent.opacity(0.16) : hovered && !added ? Color.primary.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title + (entry.detail.isEmpty ? "" : ", " + entry.detail) + (added ? ", Added" : ""))
        .accessibilityHint(added ? "Already in this Dock." : "Adds the app to this Dock.")
        .accessibilityAddTraits(.isButton)
        .help(entry.application.url.path)
    }
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
}
private struct AddLibraryPreviewStateKey: EnvironmentKey { static let defaultValue: AddLibraryPreviewState? = nil }
extension EnvironmentValues {
    var addLibraryPreview: AddLibraryPreviewState? {
        get { self[AddLibraryPreviewStateKey.self] }
        set { self[AddLibraryPreviewStateKey.self] = newValue }
    }
}
#endif
