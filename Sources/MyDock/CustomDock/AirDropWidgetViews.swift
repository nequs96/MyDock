import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AirDropWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(
            Image(systemName: "airdrop")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 54, height: 54)
                .help("Share files or links with AirDrop")
        )
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AirDropPopoutView())
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
                    .textFieldStyle(.roundedBorder)
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

private struct AirDropShareButton: NSViewRepresentable {
    var urls: [URL]

    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Choose a Sharing Service…", target: context.coordinator, action: #selector(Coordinator.showPicker(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.isEnabled = !urls.isEmpty
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.urls = urls
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
