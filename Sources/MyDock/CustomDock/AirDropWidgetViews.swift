import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AirDropWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AirDropCompactTile())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AirDropPopoutView())
    }
}

/// The AirDrop module: a Control Center toggle glyph, active while something is dragged over it,
/// with its short name under it on wider layouts.
struct AirDropDockFace: View {
    var targeted = false
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetShowsLabel) private var showsLabel
    private var showsName: Bool { layout != .icon && !WidgetModuleMetrics.isNarrow(width) && showsLabel }
    var body: some View {
        VStack(spacing: 2) {
            WidgetToggleGlyph(kind: "AirDrop", symbol: WidgetRegistry.airDropSymbol, active: targeted, diameter: showsName ? 30 : 36)
            if showsName {
                Text(targeted ? "Drop to share" : "AirDrop").font(DockDesign.Module.label).lineLimit(1)
                    .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
        }
        .moduleInsets()
    }
}

private struct AirDropCompactTile: View {
    @State private var isDropTargeted = false
    @State private var anchorView: NSView?
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.dockModuleRadius) private var moduleRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: moduleRadius, style: .continuous)
        ZStack {
            AirDropDockFace(targeted: isDropTargeted)

            AirDropTileAnchor { anchorView = $0 }
                .allowsHitTesting(false)

            if isDropTargeted {
                shape.fill(DockDesign.accent.opacity(0.12))
                    .overlay { shape.strokeBorder(DockDesign.accent, lineWidth: 1.5) }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: 54)
        .contentShape(shape)
        .onDrop(of: [UTType.fileURL, UTType.url], isTargeted: $isDropTargeted, perform: shareDroppedItems)
        .help("Drop files or links to share with AirDrop")
        .accessibilityLabel("AirDrop")
        .accessibilityHint("Drop files or links to open the macOS sharing picker")
    }

    private func shareDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let compatibleProviders = providers.compactMap { provider -> (NSItemProvider, String)? in
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                return (provider, UTType.fileURL.identifier)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                return (provider, UTType.url.identifier)
            }
            return nil
        }
        guard !compatibleProviders.isEmpty else { return false }

        AirDropDroppedItemLoader.load(compatibleProviders) { urls in
            guard !urls.isEmpty, let anchorView else { return }
            NSSharingServicePicker(items: urls)
                .show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        }
        return true
    }
}

private struct AirDropTileAnchor: NSViewRepresentable {
    var onCreate: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        onCreate(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        onCreate(view)
    }
}

enum AirDropDroppedItemLoader {
    static func load(_ providers: [(NSItemProvider, String)], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let urls = AirDropURLCollection()

        for (provider, typeIdentifier) in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let url = Self.url(from: item)
                if let url {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(urls.values)
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return validatedShareURL(url) }
        if let url = item as? NSURL { return validatedShareURL(url as URL) }
        if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
            return validatedShareURL(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let text = item as? String {
            return validatedShareURL(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func validatedShareURL(_ value: String) -> URL? {
        guard let url = URL(string: value) else { return nil }
        return validatedShareURL(url)
    }

    private static func validatedShareURL(_ url: URL) -> URL? {
        if url.isFileURL { return url }
        return DockLinkPolicy.validatedURL(url.absoluteString)
    }
}

private final class AirDropURLCollection: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !storage.contains(where: { $0.absoluteString == url.absoluteString }) else { return }
        storage.append(url)
    }

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct AirDropPopoutView: View {
    @State private var shareURLs: [URL] = []
    @State private var isDropTargeted = false
    @State private var linkText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            ZStack {
                WidgetPopoutDropArea(targeted: isDropTargeted, minHeight: 120) {
                    VStack(spacing: 6) {
                        WidgetToggleGlyph(kind: "AirDrop", symbol: WidgetRegistry.airDropSymbol, active: isDropTargeted, diameter: 44)
                        Text(isDropTargeted ? "Drop to add items" : "Drop files or links here")
                            .font(.system(size: 13, weight: .medium))
                        Text("MyDock passes them to the macOS sharing picker.")
                            .font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
                AirDropDropTarget(isTargeted: $isDropTargeted, onDrop: addURLs)
            }
            .frame(minHeight: 120)

            VStack(alignment: .leading, spacing: 6) {
                WidgetPopoutSectionHeader(shareURLs.isEmpty ? "Add Items" : "\(shareURLs.count) item\(shareURLs.count == 1 ? "" : "s") ready") {
                    if !shareURLs.isEmpty {
                        Button("Clear") { shareURLs = []; errorMessage = nil }
                    }
                }
                GroupedSection(separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    ForEach(shareURLs, id: \.absoluteString) { url in
                        WidgetPopoutRow {
                            HStack(spacing: 8) {
                                Image(systemName: url.isFileURL ? "doc" : "link").foregroundStyle(.secondary).frame(width: 18)
                                    .accessibilityHidden(true)
                                Text(url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString))
                                    .font(DockDesign.Grouped.titleFont).lineLimit(1)
                            }
                        }
                    }
                    GroupedRow("Choose Files…", role: .button, action: chooseFiles)
                    WidgetPopoutRow {
                        HStack(spacing: 8) {
                            TextField("https://example.com", text: $linkText)
                                .textFieldStyle(.plain)
                                .onSubmit(addLink)
                                .accessibilityLabel("Web link")
                            Button("Add Link", action: addLink).buttonStyle(.borderless)
                        }
                    }
                }
            }

            if !shareURLs.isEmpty {
                HStack {
                    Spacer()
                    AirDropShareButton(urls: shareURLs)
                        .frame(height: 30).fixedSize()
                }
            }
            if let errorMessage {
                WidgetPopoutCaption(errorMessage, color: .orange)
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose Items to Share"
        panel.prompt = "Add to AirDrop"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        addURLs(panel.urls)
    }

    private func addLink() {
        guard let url = AirDropLinkValidator.validatedURL(linkText) else {
            errorMessage = "Enter a complete HTTP or HTTPS link."
            return
        }
        addURLs([url])
        linkText = ""
        errorMessage = nil
    }

    private func addURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var seen = Set(shareURLs.map(\.absoluteString))
        for url in urls where seen.insert(url.absoluteString).inserted {
            shareURLs.append(url)
        }
        errorMessage = nil
    }
}

enum AirDropLinkValidator {
    static func validatedURL(_ value: String) -> URL? {
        DockLinkPolicy.validatedURL(value)
    }
}

private struct AirDropDropTarget: NSViewRepresentable {
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> AirDropDropTargetView {
        let view = AirDropDropTargetView(frame: .zero)
        view.onDropURLs = onDrop
        view.onTargetingChange = { context.coordinator.isTargeted.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ nsView: AirDropDropTargetView, context: Context) {
        nsView.onDropURLs = onDrop
        nsView.onTargetingChange = { context.coordinator.isTargeted.wrappedValue = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isTargeted: _isTargeted) }

    @Binding private var isTargeted: Bool

    init(isTargeted: Binding<Bool> = .constant(false), onDrop: @escaping ([URL]) -> Void) {
        _isTargeted = isTargeted
        self.onDrop = onDrop
    }

    final class Coordinator {
        var isTargeted: Binding<Bool>
        init(isTargeted: Binding<Bool>) { self.isTargeted = isTargeted }
    }
}

private final class AirDropDropTargetView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onTargetingChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canReadFiles = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        )
        let canReadURL = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [:]
        )
        let accepted = canReadFiles || canReadURL
        onTargetingChange?(accepted)
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetingChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetingChange?(false) }
        guard let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [:]
        ) else { return false }
        let urls = objects.compactMap { $0 as? URL }
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }
}

struct AirDropShareButton: NSViewRepresentable {
    var urls: [URL]
    var title = "Choose a Sharing Service…"

    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.showPicker(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.isEnabled = !urls.isEmpty
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.urls = urls
        button.title = title
        button.isEnabled = !urls.isEmpty
    }

    @MainActor final class Coordinator: NSObject {
        var urls: [URL]
        init(urls: [URL]) { self.urls = urls }

        @objc func showPicker(_ sender: NSButton) {
            guard !urls.isEmpty else { return }
            NSSharingServicePicker(items: urls).show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }
}
