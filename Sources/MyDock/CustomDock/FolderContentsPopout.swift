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
            HStack(spacing: 8) {
                if directoryStack.count > 1 {
                    Button { directoryStack.removeLast() } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Back")
                }
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Text(directoryStack.count == 1 ? (folderName ?? currentURL.lastPathComponent) : currentURL.lastPathComponent)
                    .font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    NSWorkspace.shared.open(currentURL)
                } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain).help("Open in Finder")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close folder")
            }
            .padding(12)
            Divider()
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading folder…").font(.caption).foregroundStyle(.secondary)
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
                                    NSWorkspace.shared.open(entry.url)
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                                        .resizable().scaledToFit().frame(width: 22, height: 22)
                                    Text(entry.name).lineLimit(1)
                                    Spacer(minLength: 6)
                                    if entry.isDirectory { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 9).padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in Finder") { NSWorkspace.shared.open(entry.url) }
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                            }
                        }
                        if let summary = listing?.omittedSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
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

    private func emptyState(title: String, symbol: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
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
