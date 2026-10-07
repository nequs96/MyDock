import AppKit
import SwiftUI

/// Explore storage: on request, scans Home, Applications and Library (or a chosen folder) for the largest
/// files. A feature of its own beside the CPU reading, with its own monitor, so a CPU sample does not
/// re-render it. Nothing is deleted or uploaded.
struct SystemStorageExplorerSection: View {
    @ObservedObject private var scanner = StorageScanMonitor.shared

    var body: some View {
        GroupedSection("Explore storage") {
            Group {
                if scanner.isScanning {
                    GroupedRow("Scanning…") { ProgressView().controlSize(.small) }
                    GroupedRow("Cancel", role: .button) { scanner.cancel() }
                } else {
                    GroupedRow("Scan Folders", role: .button) { scanner.scanDefaultLocations() }
                    GroupedRow("Choose Folder…", role: .button, action: chooseFolder)
                    if !scanner.results.isEmpty { GroupedRow("Scan Again", role: .button) { scanner.scanAgain() } }
                }
            }
            .help("Scan Home, Applications and Library, or choose a folder. Nothing is deleted or uploaded.")
            if scanner.isScanning || !scanner.warnings.isEmpty || !scanner.results.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if scanner.isScanning {
                        Text(scanner.currentPath ?? "Preparing scan…").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if let progress = scanner.progress {
                            Text(SystemStorageExplorerFormatting.progress(progress)).font(DockDesign.Grouped.subtitleFont).monospacedDigit()
                        }
                    }
                    ForEach(scanner.warnings, id: \.self) { Text($0).font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning) }
                    ForEach(scanner.results, id: \.rootPath) { result in resultView(result) }
                }
                .padding(DockDesign.Grouped.rowHorizontalPadding)
            }
        }
    }

    private func resultView(_ result: StorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.rootPath).font(DockDesign.Grouped.subtitleFont.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            Text(SystemStorageExplorerFormatting.summary(result)).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            ForEach(result.largestFiles) { file in
                Button {
                    reveal(file)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc").foregroundStyle(.secondary)
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(SystemActivityFormatting.bytes(file.byteSize)).monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }.font(DockDesign.Grouped.subtitleFont).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityHint("Reveals in Finder")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan"
        panel.prompt = "Scan"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanner.scanFolder(url)
    }

    private func reveal(_ file: StorageScanEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }
}

/// The explorer's progress and result lines, with counts grouped for the user's locale.
enum SystemStorageExplorerFormatting {
    static func progress(_ progress: StorageScanProgress, locale: Locale = .current) -> String {
        files(progress.scannedFileCount, locale: locale) + " · " + SystemActivityFormatting.bytes(progress.scannedBytes, locale: locale)
    }

    static func summary(_ result: StorageScanResult, locale: Locale = .current) -> String {
        let base = files(result.scannedFileCount, locale: locale) + " · " + SystemActivityFormatting.bytes(result.scannedBytes, locale: locale)
        guard result.skippedEntries > 0 || result.wasCapped else { return base }
        let skipped = result.skippedEntries > 0 ? " · \(result.skippedEntries.formatted(.number.locale(locale))) skipped" : ""
        let capped = result.wasCapped ? " · scan limit reached" : ""
        return "Partial · \(base)\(skipped)\(capped)"
    }

    private static func files(_ count: Int, locale: Locale) -> String {
        count.formatted(.number.locale(locale)) + (count == 1 ? " file" : " files")
    }
}

@MainActor
final class StorageScanMonitor: ObservableObject {
    static let shared = StorageScanMonitor()

    @Published private(set) var results: [StorageScanResult] = []
    @Published private(set) var progress: StorageScanProgress?
    @Published private(set) var currentPath: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var isScanning = false

    private var cancellation: StorageScanCancellationFlag?
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()
    private var previousRoots: [ScanRoot] = []

    /// One scanned location and the subtrees counted as their own location instead.
    private struct ScanRoot: Sendable {
        var url: URL
        var excluding: Set<URL> = []
    }

    func scanDefaultLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        // Home leaves out Library, which is its own location, so the three totals are disjoint.
        start([ScanRoot(url: home, excluding: [library]),
               ScanRoot(url: URL(fileURLWithPath: "/Applications", isDirectory: true)),
               ScanRoot(url: library)])
    }

    func scanFolder(_ url: URL) { start([ScanRoot(url: url)]) }
    func scanAgain() { start(previousRoots) }
    func cancel() { cancellation?.cancel() }

    private func start(_ roots: [ScanRoot]) {
        guard !isScanning, !roots.isEmpty else { return }
        previousRoots = roots
        results = []
        warnings = []
        progress = nil
        isScanning = true
        let flag = StorageScanCancellationFlag()
        cancellation = flag
        let identifier = UUID()
        scanID = identifier

        scanTask = Task { [weak self] in
            guard let self else { return }
            for scanRoot in roots {
                guard !flag.isCancelled else { break }
                let root = scanRoot.url, excluded = scanRoot.excluding
                self.currentPath = root.path
                self.progress = StorageScanProgress(visitedEntries: 0, scannedFileCount: 0, scannedBytes: 0)
                let work = Task.detached(priority: .userInitiated) { [self] in
                    try StorageScanner.scan(at: root, cancellation: flag, excluding: excluded) { update in
                        Task { @MainActor [self] in
                            guard self.scanID == identifier, self.isScanning else { return }
                            self.progress = update
                        }
                    }
                }
                do {
                    let result = try await work.value
                    self.results.append(result)
                } catch StorageScanner.ScanError.cancelled {
                    break
                } catch {
                    self.warnings.append("\(root.path): \(error.localizedDescription)")
                }
            }
            guard self.scanID == identifier else { return }
            self.currentPath = nil
            self.progress = nil
            self.cancellation = nil
            self.isScanning = false
            self.scanTask = nil
        }
    }
}
