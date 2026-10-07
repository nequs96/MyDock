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
    /// `durationScale` converts the player's duration unit to seconds: Spotify reports milliseconds, Music seconds.
    static func snapshot(from response: String, updatedAt: Date = .now, durationScale: Double = 1) throws -> NowPlayingSnapshot? {
        guard !response.isEmpty else { return nil }
        let parts = response.trimmingCharacters(in: .newlines).components(separatedBy: response.contains("\u{1f}") ? "\u{1f}" : "\n")
        guard parts.count >= 6,
              let position = number(parts[4]), let rawDuration = number(parts[5]),
              position.isFinite, rawDuration.isFinite else { throw NowPlayingParsingError.malformedResponse }
        let duration = rawDuration * durationScale
        return NowPlayingSnapshot(title: parts[0],
                                  artist: parts[1],
                                  album: parts[2],
                                  isPlaying: parts[3].localizedCaseInsensitiveContains("playing"),
                                  position: max(0, position),
                                  duration: max(0, duration),
                                  updatedAt: updatedAt,
                                  artworkURL: parts.count > 6 ? NowPlayingArtwork.spotifyURL(from: parts[6]) : nil)
    }

    /// AppleScript writes reals with the user's decimal separator ("12,5" in many regions).
    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

enum NowPlayingVisibilityPolicy {
    static func showsTile(hideWhenClosed: Bool, enabledSources: Set<NowPlayingSource>,
                          runningSources: Set<NowPlayingSource>) -> Bool {
        !hideWhenClosed || !enabledSources.isDisjoint(with: runningSources)
    }

    static func showsTile(hideWhenClosed: Bool, source: NowPlayingSource,
                          runningSources: Set<NowPlayingSource>) -> Bool {
        showsTile(hideWhenClosed: hideWhenClosed, enabledSources: [source], runningSources: runningSources)
    }
}

enum NowPlayingSourcePolicy {
    static func activeSource(preferred: NowPlayingSource,
                             enabledSources: Set<NowPlayingSource>,
                             snapshots: [NowPlayingSource: NowPlayingSnapshot]) -> NowPlayingSource? {
        guard !enabledSources.isEmpty else { return nil }
        let playingSources = enabledSources.compactMap { source -> (NowPlayingSource, NowPlayingSnapshot)? in
            guard let snapshot = snapshots[source], snapshot.isPlaying else { return nil }
            return (source, snapshot)
        }
        if playingSources.count == 1 { return playingSources[0].0 }
        if !playingSources.isEmpty {
            if playingSources.contains(where: { $0.0 == preferred }) { return preferred }
            return playingSources.max(by: { $0.1.updatedAt < $1.1.updatedAt })?.0
        }
        if enabledSources.contains(preferred) { return preferred }
        return NowPlayingSource.allCases.first(where: enabledSources.contains)
    }
}

enum NowPlayingObservationKind: Equatable {
    case compact
    case popout
}

enum NowPlayingRefreshPolicy {
    static func interval(dockIsVisible: Bool, kinds: [NowPlayingObservationKind]) -> TimeInterval? {
        // A visible popout needs fresh data even while the Dock is hidden.
        let visibleKinds = dockIsVisible ? kinds : kinds.filter { $0 == .popout }
        guard !visibleKinds.isEmpty else { return nil }
        return visibleKinds.contains(where: { $0 == .popout }) ? 5 : 15
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
    private var schedulerDemand: RefreshDemandToken?
    private var pendingReads: [NowPlayingSource: Task<Void, Never>] = [:]
    private var commandTasks: [NowPlayingSource: Task<Void, Never>] = [:]

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
        RefreshScheduler.shared.setDemand(&schedulerDemand, kind: .popout,
                                          active: subscribers.values.contains { $0.kind == .popout })
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

        guard pendingReads[source] == nil else { return }
        pendingReads[source] = Task { [weak self] in
            guard let self else { return }
            defer { pendingReads[source] = nil }
        let artworkStatement = source == .spotify
            ? "try\nset trackArtworkURL to artwork url of current track as text\nend try"
            : ""
        // Checked outside the tell block: an Apple Event to a player that is quitting would launch it again.
        let script = """
        if application id "\(source.bundleIdentifier)" is not running then return ""
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
            set separator to ASCII character 31
            return trackName & separator & trackArtist & separator & trackAlbum & separator & playbackState & separator & playbackPosition & separator & trackDuration & separator & trackArtworkURL
        end tell
        """
        guard let result = await execute(script, source: source), !Task.isCancelled else { return }
        do {
            guard let snapshot = try NowPlayingResponseParser.snapshot(from: result, durationScale: source == .spotify ? 0.001 : 1) else {
                snapshots[source] = nil
                errors[source] = nil
                clearArtwork(source)
                return
            }
            snapshots[source] = snapshot
            errors[source] = nil
            updateArtwork(for: snapshot, source: source)
        } catch {
            errors[source] = "The player returned track data MyDock couldn't read."
        }
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
            action = "set targetPosition to player position - \(max(1, Int((seconds.isFinite ? min(max(0, seconds), 86_400) : 1).rounded()))); if targetPosition < 0 then set targetPosition to 0; set player position to targetPosition"
        case let .seekForward(seconds):
            action = "set targetPosition to player position + \(max(1, Int((seconds.isFinite ? min(max(0, seconds), 86_400) : 1).rounded()))); set player position to targetPosition"
        }
        let script = """
        tell application id "\(source.bundleIdentifier)"
            if it is running then
                \(action)
            end if
        end tell
        """
        let previous = commandTasks[source]
        commandTasks[source] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            // A user action: allow time for the first-run Automation consent prompt.
            _ = await execute(script, source: source, timeout: 60)
            refresh(source)
        }
    }

    private func clearTerminatedPlayer(from notification: Notification) {
        refreshRunningSources()
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleIdentifier = application.bundleIdentifier,
              let source = NowPlayingSource.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        pendingReads[source]?.cancel()
        commandTasks[source]?.cancel()
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
            artworkTasks[source] = Task { [weak self] in
                guard let self else { return }
                let response = await musicArtworkResponse()
                // Hex decoding and image downsampling run off the main thread.
                let decoded = await Task.detached(priority: .utility) {
                    response.flatMap(BoundedAutomationRunner.artworkData(from:)).flatMap(NowPlayingArtwork.decodedThumbnail(from:))
                }.value
                guard !Task.isCancelled, artworkKeys[source] == key else { return }
                artwork[source] = decoded?.image
                artworkTasks[source] = nil
            }
        case .spotify:
            guard let url = snapshot.artworkURL else { return }
            artworkTasks[source] = Task { [weak self] in
                let data = await NowPlayingArtwork.fetchSpotifyArtwork(at: url)
                let decoded = await Task.detached(priority: .utility) {
                    data.flatMap(NowPlayingArtwork.decodedThumbnail(from:))
                }.value
                guard let self, self.artworkKeys[source] == key, !Task.isCancelled else { return }
                self.artwork[source] = decoded?.image
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

    /// The raw `«data …»` reply; decoding happens off the main actor.
    private func musicArtworkResponse() async -> String? {
        let script = """
        if application id "com.apple.Music" is not running then return missing value
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        return try? await BoundedAutomationRunner.run(script, sourceForm: true, maximumBytes: 4 * 1_024 * 1_024)
    }

    private func execute(_ sourceText: String, source: NowPlayingSource, timeout: TimeInterval = 8) async -> String? {
        do {
            let response = try await BoundedAutomationRunner.run(sourceText, timeout: timeout)
            guard !Task.isCancelled else { return nil }
            errors[source] = nil
            return response
        } catch {
            guard !Task.isCancelled else { return nil }
            errors[source] = NowPlayingCopy.automationMessage(for: error, sourceTitle: source.title)
            return nil
        }
    }
}

/// Typed osascript failure. Parsed only from exit status and stderr; never from stdout.
enum AutomationError: Error, Equatable {
    case permissionDenied
    case failed(exitStatus: Int32)

    /// Apple Event authorization failures: error -1743 ("Not authorized to send Apple events to ...").
    /// -1744 means a pending user-consent prompt, which also needs the user to act in System Settings or the prompt.
    static func classify(exitStatus: Int32, standardError: Data) -> AutomationError {
        let text = String(decoding: standardError.prefix(4_096), as: UTF8.self)
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not authorized to send apple events") {
            return .permissionDenied
        }
        return .failed(exitStatus: exitStatus)
    }
}

enum BoundedAutomationRunner {
    /// `timeout` bounds background reads; explicit user actions pass a longer one, because the first
    /// Apple Event to an app waits for the user to answer the Automation consent prompt.
    static func run(_ source: String, sourceForm: Bool = false, maximumBytes: Int = 65_536,
                    timeout: TimeInterval = 8) async throws -> String {
        try AppRuntimeEnvironment.requireNativeEffects()
        let output = try await BoundedSubprocessCapture.runCancellable(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-s", sourceForm ? "s" : "h", "-e", source],
            maximumOutputBytes: maximumBytes, maximumErrorBytes: 4_096, timeout: timeout)
        guard output.terminationStatus == 0 else {
            throw AutomationError.classify(exitStatus: output.terminationStatus, standardError: output.standardError)
        }
        return String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// Decodes `«data TYPE0123…»` over UTF-8 bytes: megabytes of hex must not walk grapheme clusters.
    static func artworkData(from response: String) -> Data? {
        guard response.hasPrefix("«data "), response.hasSuffix("»") else { return nil }
        let body = response.dropFirst(6).dropLast()
        // Skip the four-character type code (PNGf, JPEG, …).
        guard let payloadStart = body.index(body.startIndex, offsetBy: 4, limitedBy: body.endIndex) else { return nil }
        let hex = body[payloadStart...].utf8
        let byteCount = hex.count
        guard byteCount <= 4 * 1_024 * 1_024, byteCount.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: byteCount / 2)
        var high: UInt8?
        for character in hex {
            guard let nibble = hexValue(character) else { return nil }
            if let pending = high {
                data.append(pending << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case 0x30...0x39: return character - 0x30
        case 0x41...0x46: return character - 0x41 + 10
        case 0x61...0x66: return character - 0x61 + 10
        default: return nil
        }
    }
}

enum NowPlayingCopy {
    static func automationMessage(for error: Error, sourceTitle: String) -> String {
        if (error as? AutomationError) == .permissionDenied {
            return "MyDock is not allowed to control \(sourceTitle). Turn on Automation for MyDock in System Settings \u{2192} Privacy & Security \u{2192} Automation, then try again."
        }
        if (error as? BoundedSubprocessCaptureError) == .timedOut {
            return "\(sourceTitle) did not respond in time. If macOS asks for permission, allow it, then try again."
        }
        return "MyDock couldn't read or control \(sourceTitle). The player may be unresponsive or quit; try again."
    }
}
