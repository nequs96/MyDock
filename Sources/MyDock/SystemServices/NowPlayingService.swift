import AppKit
import Combine
import Foundation

struct NowPlayingSnapshot: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var updatedAt: Date
    var artworkURL: URL?
}

enum NowPlayingCommand {
    case previousTrack
    case togglePlayback
    case nextTrack
    case seekBackward(TimeInterval)
    case seekForward(TimeInterval)
}

enum NowPlayingParsingError: Error {
    case malformedResponse
}

enum NowPlayingResponseParser {
    static func snapshot(from response: String, updatedAt: Date = .now) throws -> NowPlayingSnapshot? {
        guard !response.isEmpty else { return nil }
        let parts = response.components(separatedBy: "\n")
        guard parts.count >= 6,
              let position = Double(parts[4]), let duration = Double(parts[5]),
              position.isFinite, duration.isFinite else { throw NowPlayingParsingError.malformedResponse }
        return NowPlayingSnapshot(title: parts[0],
                                  artist: parts[1],
                                  album: parts[2],
                                  isPlaying: parts[3].localizedCaseInsensitiveContains("playing"),
                                  position: max(0, position),
                                  duration: max(0, duration),
                                  updatedAt: updatedAt,
                                  artworkURL: parts.count > 6 ? NowPlayingArtwork.spotifyURL(from: parts[6]) : nil)
    }
}

enum NowPlayingVisibilityPolicy {
    static func showsTile(hideWhenClosed: Bool, source: NowPlayingSource,
                          runningSources: Set<NowPlayingSource>) -> Bool {
        !hideWhenClosed || runningSources.contains(source)
    }
}

enum NowPlayingObservationKind: Equatable {
    case compact
    case popout
}

enum NowPlayingRefreshPolicy {
    static func interval(dockIsVisible: Bool, kinds: [NowPlayingObservationKind]) -> TimeInterval? {
        guard dockIsVisible, !kinds.isEmpty else { return nil }
        return kinds.contains(where: { $0 == .popout }) ? 5 : 15
    }
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let shared = NowPlayingMonitor()

    @Published private(set) var snapshots: [NowPlayingSource: NowPlayingSnapshot] = [:]
    @Published private(set) var errors: [NowPlayingSource: String] = [:]
    @Published private(set) var runningSources: Set<NowPlayingSource> = []
    @Published private(set) var artwork: [NowPlayingSource: NSImage] = [:]
    private var applicationObservation: AnyCancellable?
    private var applicationLaunchObservation: AnyCancellable?
    private var artworkKeys: [NowPlayingSource: String] = [:]
    private var artworkTasks: [NowPlayingSource: Task<Void, Never>] = [:]
    private var subscribers: [UUID: (source: NowPlayingSource, kind: NowPlayingObservationKind)] = [:]
    private var refreshTasks: [NowPlayingSource: Task<Void, Never>] = [:]
    private var refreshIntervals: [NowPlayingSource: TimeInterval] = [:]
    private var dockIsVisible = false

    private init() {
        refreshRunningSources()
        applicationObservation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in self?.clearTerminatedPlayer(from: notification) }
            }
        applicationLaunchObservation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshRunningSources() }
            }
    }

    private func refreshRunningSources() {
        runningSources = Set(NowPlayingSource.allCases.filter { source in
            NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier)
                .contains(where: { !$0.isTerminated })
        })
    }

    func setDockVisible(_ visible: Bool) {
        guard dockIsVisible != visible else { return }
        dockIsVisible = visible
        for source in NowPlayingSource.allCases { updateRefreshTask(for: source) }
    }

    func subscribe(_ identifier: UUID, to source: NowPlayingSource, kind: NowPlayingObservationKind) {
        let previous = subscribers[identifier]?.source
        subscribers[identifier] = (source, kind)
        if let previous, previous != source { updateRefreshTask(for: previous) }
        updateRefreshTask(for: source)
    }

    func unsubscribe(_ identifier: UUID) {
        guard let source = subscribers.removeValue(forKey: identifier)?.source else { return }
        updateRefreshTask(for: source)
    }

    private func updateRefreshTask(for source: NowPlayingSource) {
        let kinds = subscribers.values.filter { $0.source == source }.map(\.kind)
        let desired = NowPlayingRefreshPolicy.interval(dockIsVisible: dockIsVisible, kinds: kinds)
        guard refreshIntervals[source] != desired else { return }
        refreshTasks[source]?.cancel()
        refreshTasks[source] = nil
        refreshIntervals[source] = desired
        guard let desired else { return }
        refreshTasks[source] = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.refresh(source)
            for await _ in RefreshScheduler.shared.ticks(every: desired) {
                guard !Task.isCancelled else { return }
                self?.refresh(source)
            }
        }
    }

    func refresh(_ source: NowPlayingSource) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).contains(where: { !$0.isTerminated }) else {
            snapshots[source] = nil
            errors[source] = nil
            clearArtwork(source)
            return
        }

        let artworkStatement = source == .spotify
            ? "try\nset trackArtworkURL to artwork url of current track as text\nend try"
            : ""
        let script = """
        tell application id "\(source.bundleIdentifier)"
            if player state is stopped then return ""
            set trackName to name of current track as text
            set trackArtist to artist of current track as text
            set trackAlbum to album of current track as text
            set playbackState to player state as text
            set playbackPosition to player position as text
            set trackDuration to duration of current track as text
            set trackArtworkURL to ""
            \(artworkStatement)
            return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & playbackState & linefeed & playbackPosition & linefeed & trackDuration & linefeed & trackArtworkURL
        end tell
        """
        guard let result = execute(script, source: source) else {
            snapshots[source] = nil
            clearArtwork(source)
            return
        }
        do {
            guard let snapshot = try NowPlayingResponseParser.snapshot(from: result) else {
                snapshots[source] = nil
                errors[source] = nil
                clearArtwork(source)
                return
            }
            snapshots[source] = snapshot
            errors[source] = nil
            updateArtwork(for: snapshot, source: source)
        } catch {
            snapshots[source] = nil
            clearArtwork(source)
            errors[source] = "The player returned track data MyDock couldn't read."
        }
    }

    func perform(_ command: NowPlayingCommand, source: NowPlayingSource) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).contains(where: { !$0.isTerminated }) else {
            errors[source] = "Open \(source.title) before using playback controls."
            return
        }

        let action: String
        switch command {
        case .previousTrack: action = "previous track"
        case .togglePlayback: action = "playpause"
        case .nextTrack: action = "next track"
        case let .seekBackward(seconds):
            action = "set targetPosition to player position - \(max(1, Int(seconds.rounded()))); if targetPosition < 0 then set targetPosition to 0; set player position to targetPosition"
        case let .seekForward(seconds):
            action = "set targetPosition to player position + \(max(1, Int(seconds.rounded()))); set player position to targetPosition"
        }
        let script = """
        tell application id "\(source.bundleIdentifier)"
            if it is running then
                \(action)
            end if
        end tell
        """
        _ = execute(script, source: source)
        refresh(source)
    }

    private func clearTerminatedPlayer(from notification: Notification) {
        refreshRunningSources()
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleIdentifier = application.bundleIdentifier,
              let source = NowPlayingSource.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        snapshots[source] = nil
        errors[source] = nil
        clearArtwork(source)
    }

    private func updateArtwork(for snapshot: NowPlayingSnapshot, source: NowPlayingSource) {
        let key = "\(snapshot.title)\u{1f}\(snapshot.artist)\u{1f}\(snapshot.album)\u{1f}\(snapshot.duration)"
        guard artworkKeys[source] != key else { return }
        clearArtwork(source)
        artworkKeys[source] = key
        switch source {
        case .appleMusic:
            if let data = musicArtworkData() {
                artwork[source] = NowPlayingArtwork.thumbnail(from: data)
            }
        case .spotify:
            guard let url = snapshot.artworkURL else { return }
            artworkTasks[source] = Task { [weak self] in
                let data = await NowPlayingArtwork.fetchSpotifyArtwork(at: url)
                guard let self, self.artworkKeys[source] == key, !Task.isCancelled else { return }
                self.artwork[source] = data.flatMap { NowPlayingArtwork.thumbnail(from: $0) }
                self.artworkTasks[source] = nil
            }
        }
    }

    private func clearArtwork(_ source: NowPlayingSource) {
        artworkTasks[source]?.cancel()
        artworkTasks[source] = nil
        artworkKeys[source] = nil
        artwork[source] = nil
    }

    private func musicArtworkData() -> Data? {
        let scriptText = """
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        guard let script = NSAppleScript(source: scriptText) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        return result.data
    }

    private func execute(_ sourceText: String, source: NowPlayingSource) -> String? {
        guard let script = NSAppleScript(source: sourceText) else {
            errors[source] = "MyDock couldn't prepare the playback command."
            return nil
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            errors[source] = "MyDock couldn't read or control \(source.title). Check System Settings → Privacy & Security → Automation."
            return nil
        }
        return result.stringValue ?? ""
    }
}
