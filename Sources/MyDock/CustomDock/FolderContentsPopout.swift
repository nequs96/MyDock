import AppKit
import SwiftUI

struct FolderContentsPopout: View {
    var folderURL: URL
    var folderName: String?
    var onClose: () -> Void

    @State private var directoryStack: [URL]
    @State private var listing: FolderContentsListing?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var requests = FolderLoadRequestTracker()

    init(folderURL: URL, folderName: String? = nil, onClose: @escaping () -> Void) {
        self.folderURL = folderURL
        self.folderName = folderName
        self.onClose = onClose
        _directoryStack = State(initialValue: [folderURL])
    }

    private var currentURL: URL { directoryStack.last ?? folderURL }

    var body: some View {
        VStack(spacing: 0) {
            // The widget popout header: a quiet glyph and name, then circle buttons.
            HStack(spacing: 8) {
                if directoryStack.count > 1 {
                    Button { directoryStack.removeLast() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(WidgetCircleButtonStyle())
                        .keyboardShortcut("[", modifiers: .command)
                        .accessibilityLabel("Back")
                        .help("Back (⌘[)")
                }
                Image(systemName: "folder.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(directoryStack.count == 1 ? (folderName ?? currentURL.lastPathComponent) : currentURL.lastPathComponent)
                    .font(DockDesign.Grouped.titleFont.weight(.semibold)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button {
                    openItem(currentURL)
                } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(WidgetCircleButtonStyle()).accessibilityLabel("Open in Finder").help("Open in Finder")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(WidgetCircleButtonStyle()).accessibilityLabel("Close Folder").help("Close folder")
            }
            .padding(12)
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading folder…").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else if let errorMessage {
                emptyState(title: "Folder unavailable", symbol: "folder.badge.questionmark", message: errorMessage)
            } else if listing?.isEmpty ?? true {
                emptyState(title: "Empty folder", symbol: "folder", message: "This folder has no visible items.")
            } else {
                DockScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(listing?.entries ?? []) { entry in
                            Button {
                                if entry.isDirectory {
                                    directoryStack.append(entry.url)
                                } else {
                                    openItem(entry.url)
                                }
                            } label: {
                                HStack(spacing: DockDesign.Grouped.glyphSpacing) {
                                    Image(nsImage: FolderEntryIcon.image(for: entry.url))
                                        .resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
                                    Text(entry.name).font(DockDesign.Grouped.titleFont).lineLimit(1)
                                    Spacer(minLength: 6)
                                    if entry.isDirectory {
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding).padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(entry.isDirectory ? "Shows this folder's contents" : "Opens in its default app")
                            .contextMenu {
                                // A file opens in its default app, so the item says Open; Reveal in Finder shows it in Finder.
                                Button("Open") { openItem(entry.url) }
                                Button("Reveal in Finder") {
                                    guard AppRuntimeEnvironment.allowsNativeEffects else { return }
                                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                                }
                            }
                        }
                        if let summary = listing?.omittedSummary {
                            Text(summary).font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 330, height: 360).background(DockDesign.page).font(DockDesign.body).modifier(MyDockInterfaceStyle())
        .task(id: currentURL) { await loadEntries(at: currentURL) }
        .onExitCommand(perform: onClose)
    }

    /// Opening launches apps or drives Finder, so isolated validation sessions never do it.
    private func openItem(_ url: URL) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        NSWorkspace.shared.open(url)
    }

    /// The same status hero the widget popouts use.
    private func emptyState(title: String, symbol: String, message: String) -> some View {
        WidgetPopoutHero(value: title, caption: message, symbol: symbol, forcedStyle: .status)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
    }

    private func loadEntries(at url: URL) async {
        let token = requests.begin()
        // Clear rows from the previous folder so stale items are never shown for the new target.
        listing = nil
        errorMessage = nil
        isLoading = true
        do {
            let loaded = try await FolderContentsReader.load(at: url)
            guard !Task.isCancelled, requests.isCurrent(token), currentURL == url else { return }
            listing = loaded
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requests.isCurrent(token), currentURL == url else { return }
            listing = nil
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

/// Folder row icons, fetched once per path instead of on every render while scrolling.
@MainActor
enum FolderEntryIcon {
    private static let cache: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 512; return cache }()

    static func image(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
