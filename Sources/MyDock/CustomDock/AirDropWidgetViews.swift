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

private struct AirDropCompactTile: View {
    @State private var isDropTargeted = false
    @State private var anchorView: NSView?

    var body: some View {
        ZStack {
            Image(systemName: WidgetRegistry.airDropSymbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.tint)

            AirDropTileAnchor { anchorView = $0 }
                .allowsHitTesting(false)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 54, height: 54)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Share with AirDrop").font(.headline)
            Text("Choose files, drop them here, or add a web link. MyDock passes the selected items to the macOS sharing picker.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.tint)
                    Text(isDropTargeted ? "Drop to add items" : "Drop files or links here")
                        .font(.callout.weight(.medium))
                }
                AirDropDropTarget(isTargeted: $isDropTargeted, onDrop: addURLs)
            }
            .frame(height: 96)

            HStack(spacing: 8) {
                Button("Choose Files…", action: chooseFiles)
                if !shareURLs.isEmpty {
                    Text("\(shareURLs.count) item\(shareURLs.count == 1 ? "" : "s") ready")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !shareURLs.isEmpty {
                    Button("Clear") { shareURLs = []; errorMessage = nil }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("https://example.com", text: $linkText)
                    .textFieldStyle(DockTextFieldStyle())
                    .onSubmit(addLink)
                Button("Add Link", action: addLink)
            }

            if !shareURLs.isEmpty {
                AirDropShareButton(urls: shareURLs)
                    .frame(height: 30)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 4)
        .frame(width: 340)
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
