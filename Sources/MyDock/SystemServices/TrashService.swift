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

    static let isolatedMessage = "Trash is unavailable in isolated validation."
    private let trashURL: URL
    private let allowsNativeEffects: Bool
    /// Test seam: number of filesystem watches attempted by this instance.
    private(set) var watchAttemptCount = 0
    private var source: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?
    private var fallbackRefreshTask: Task<Void, Never>?

    private convenience init() {
        self.init(trashURL: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".Trash", isDirectory: true),
                  allowsNativeEffects: AppRuntimeEnvironment.allowsNativeEffects)
    }

    init(trashURL: URL, allowsNativeEffects: Bool) {
        self.trashURL = trashURL
        self.allowsNativeEffects = allowsNativeEffects
        guard allowsNativeEffects else {
            errorMessage = Self.isolatedMessage
            return
        }
        startWatching()
        refresh()
    }

    func refresh() {
        guard allowsNativeEffects else { return }
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
        guard allowsNativeEffects else { return }
        watchAttemptCount += 1
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
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    static func emptyTrash() async throws {
        do {
            _ = try await BoundedAutomationRunner.run("tell application id \"com.apple.finder\" to empty trash")
        } catch {
            throw TrashActionError.failed(TrashCopy.emptyFailureMessage(for: error))
        }
    }
}

/// User-facing Trash wording. Finder's `empty trash` covers every mounted volume, while MyDock counts and opens only ~/.Trash.
enum TrashCopy {
    static let countScope = "Items in your home Trash (~/.Trash)"
    static let emptyConfirmationTitle = "Empty the Trash on all volumes?"
    static let emptyConfirmationMessage = "This permanently deletes everything in Finder's Trash on all volumes, including items on external drives that are not counted here. It cannot be undone. Finder may show its own confirmation."
    static let emptyButton = "Empty Trash on All Volumes"
    static let emptyHelp = "Asks Finder to empty the Trash on all volumes. The count shows only your home Trash."

    static func countLabel(_ count: Int) -> String { count == 1 ? "1 item in home Trash" : "\(count) items in home Trash" }

    /// The automation runner reports every non-zero osascript exit the same way, so describe the likely causes without claiming one.
    static func emptyFailureMessage(for error: Error) -> String {
        if let known = error as? TrashActionError, case let .failed(message) = known { return message }
        if let automation = error as? AutomationError {
            if automation == .permissionDenied {
                return "MyDock is not allowed to control Finder. Turn on Automation for MyDock \u{2192} Finder in System Settings \u{2192} Privacy & Security \u{2192} Automation, then try again."
            }
            return "Finder did not confirm that the Trash was emptied. Some items may not have been deleted. Open Trash in Finder to check what remains."
        }
        if error is NowPlayingParsingError {
            return "Finder did not confirm that the Trash was emptied. Automation access for Finder may be denied (System Settings \u{2192} Privacy & Security \u{2192} Automation), or some items could not be deleted. Open Trash in Finder to check what remains."
        }
        return error.localizedDescription
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
