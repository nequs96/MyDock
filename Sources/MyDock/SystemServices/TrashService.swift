import AppKit
import Combine
import Darwin
import Foundation

enum TrashContentsReader {
    static func itemCount(at trashURL: URL, fileManager: FileManager = .default) throws -> Int {
        do {
            return try fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []).count
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError { return 0 }
            throw error
        }
    }
}

@MainActor
final class TrashStatus: ObservableObject {
    static let shared = TrashStatus()

    @Published private(set) var itemCount = 0
    @Published private(set) var errorMessage: String?

    private let trashURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".Trash", isDirectory: true)
    private var source: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?
    private var fallbackRefreshTask: Task<Void, Never>?

    private init() {
        startWatching()
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        let url = trashURL
        refreshTask = Task { @MainActor [weak self] in
            do {
                let count = try await Task.detached(priority: .utility) {
                    try TrashContentsReader.itemCount(at: url)
                }.value
                guard !Task.isCancelled else { return }
                self?.itemCount = count
                self?.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.itemCount = 0
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func startWatching() {
        let descriptor = open(trashURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleFallbackRefresh()
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if source?.data.contains(.delete) == true || source?.data.contains(.rename) == true {
                    source?.cancel(); source = nil; scheduleFallbackRefresh()
                }
                refresh()
            }
        }
        watcher.setCancelHandler { close(descriptor) }
        source = watcher
        watcher.resume()
    }

    private func scheduleFallbackRefresh() {
        fallbackRefreshTask?.cancel()
        fallbackRefreshTask = Task { [weak self] in
            for await _ in RefreshScheduler.shared.ticks(every: 30) {
                guard !Task.isCancelled else { return }
                if self?.source == nil { self?.startWatching() }
                self?.refresh()
            }
        }
    }
}

@MainActor
enum TrashActions {
    static func openTrash() {
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    static func emptyTrash() async throws {
        _ = try await BoundedAutomationRunner.run("tell application id \"com.apple.finder\" to empty trash")
    }
}

enum TrashActionError: LocalizedError {
    case scriptUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable: "The macOS Trash action is unavailable."
        case let .failed(message): message
        }
    }
}
