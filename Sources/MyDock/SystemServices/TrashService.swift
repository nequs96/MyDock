import AppKit
import Combine
import Darwin
import Foundation

enum TrashContentsReader {
    /// Files Finder writes into the Trash for its own bookkeeping; they are not items the user threw away.
    static let finderBookkeepingNames: Set<String> = [".DS_Store", ".localized"]

    static func itemCount(at trashURL: URL, fileManager: FileManager = .default) throws -> Int {
        do {
            return try fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [])
                .filter { !finderBookkeepingNames.contains($0.lastPathComponent) }.count
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError { return 0 }
            throw error
        }
    }

    /// macOS protects ~/.Trash: without Full Disk Access, listing it fails with a permission error.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError { return true }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionDenied(underlying) }
        return false
    }
}

@MainActor
final class TrashStatus: ObservableObject {
    static let shared = TrashStatus()

    @Published private(set) var itemCount = 0
    @Published private(set) var errorMessage: String?
    /// The home Trash could not be read because MyDock does not have Full Disk Access. Not an error: emptying
    /// still works through Finder.
    @Published private(set) var needsFullDiskAccess = false

    static let isolatedMessage = "Trash is unavailable in isolated validation."
    private let trashURL: URL
    private let allowsNativeEffects: Bool
    /// Test seam: number of filesystem watches attempted by this instance.
    private(set) var watchAttemptCount = 0
    private var source: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?
    private var fallbackRefreshTask: Task<Void, Never>?
    private var activationObservation: AnyCancellable?

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
        // Full Disk Access is granted in System Settings; check again when MyDock becomes active.
        activationObservation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.needsFullDiskAccess else { return }
                    self.refresh()
                }
            }
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
                guard !Task.isCancelled, let self else { return }
                itemCount = count
                errorMessage = nil
                if needsFullDiskAccess {
                    needsFullDiskAccess = false
                    if source == nil { startWatching() }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                itemCount = 0
                if TrashContentsReader.isPermissionDenied(error) {
                    // Polling cannot grant access, so it stops until access changes.
                    needsFullDiskAccess = true
                    errorMessage = nil
                    fallbackRefreshTask?.cancel()
                    fallbackRefreshTask = nil
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startWatching() {
        guard allowsNativeEffects else { return }
        watchAttemptCount += 1
        let descriptor = open(trashURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // A protected Trash cannot be watched without Full Disk Access, and polling would not change that.
            let failure = errno
            if failure != EPERM && failure != EACCES { scheduleFallbackRefresh() }
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
            let message = TrashCopy.emptyFailureMessage(for: error)
            throw TrashCopy.mayNeedAutomation(error) ? TrashActionError.automationDenied(message) : TrashActionError.failed(message)
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
    static let fullDiskAccessMessage = "Allow Full Disk Access to count the items in your Trash."
    static let fullDiskAccessButton = "Allow Full Disk Access…"

    static func countLabel(_ count: Int) -> String { count == 1 ? "1 item in home Trash" : "\(count) items in home Trash" }

    /// Whether a failed empty may be Finder automation being denied, so the alert can offer its setting.
    static func mayNeedAutomation(_ error: Error) -> Bool {
        (error as? AutomationError) == .permissionDenied || error is NowPlayingParsingError
    }

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
    /// Finder did not empty the Trash and Automation access for it may be denied.
    case automationDenied(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable: "The macOS Trash action is unavailable."
        case let .failed(message), let .automationDenied(message): message
        }
    }

    var suggestsAutomationSettings: Bool {
        if case .automationDenied = self { return true }
        return false
    }
}
