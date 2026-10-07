import AppKit
import SwiftUI

struct NowPlayingWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(NowPlayingCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(NowPlayingPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

#if DEBUG
/// Render-QA seam: a fixed track instead of asking Apple Music or Spotify, set only by DEBUG exports.
@MainActor
enum NowPlayingQAFixture {
    static var override: (source: NowPlayingSource, snapshot: NowPlayingSnapshot)?
    static var runningSources: Set<NowPlayingSource>?
}
#endif

/// Pure helpers for the Now Playing popout.
enum NowPlayingPresentation {
    /// "1:14", or "1:15:30" from an hour on, as Apple's players show long podcasts and audiobooks.
    static func timeString(_ time: TimeInterval) -> String {
        let seconds = time.isFinite ? max(0, Int(min(time, 359_999).rounded())) : 0
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    /// The position now: a playing track advances from its last poll, so the popout ticks every second
    /// instead of stepping by the poll interval; it never passes the track's end.
    static func position(_ snapshot: NowPlayingSnapshot, now: Date) -> TimeInterval {
        guard snapshot.isPlaying, snapshot.position.isFinite else { return snapshot.position }
        let advanced = snapshot.position + max(0, now.timeIntervalSince(snapshot.updatedAt))
        guard snapshot.duration.isFinite, snapshot.duration > 0 else { return advanced }
        return min(snapshot.duration, advanced)
    }
    static func progress(position: TimeInterval, duration: TimeInterval) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// The seek glyph that shows the actual skip interval ("gobackward.15", "goforward.30"). SF Symbols
    /// has numbered variants only for some intervals (5, 10, 15, 30, 45, 60…); any other interval, or a
    /// system without the variant, falls back to the plain arrow.
    static func seekSymbol(forward: Bool, seconds: Int, isAvailable: (String) -> Bool = symbolExists) -> String {
        let base = forward ? "goforward" : "gobackward"
        let numbered = "\(base).\(seconds)"
        return isAvailable(numbered) ? numbered : base
    }

    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

private struct NowPlayingCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @Environment(\.widgetLayout) private var dockLayout
    var item: DockItem
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var subscriptionIDs: [NowPlayingSource: UUID] = [:]

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var enabledSources: Set<NowPlayingSource> { Set(configuration.nowPlayingEnabledSources) }
    private var activeSource: NowPlayingSource? {
        #if DEBUG
        if let fixture = NowPlayingQAFixture.override { return fixture.source }
        #endif
        return NowPlayingSourcePolicy.activeSource(preferred: configuration.nowPlayingSource,
                                                   enabledSources: enabledSources,
                                                   snapshots: monitor.snapshots)
    }
    private var snapshot: NowPlayingSnapshot? {
        #if DEBUG
        if let fixture = NowPlayingQAFixture.override { return fixture.snapshot }
        #endif
        return activeSource.flatMap { monitor.snapshots[$0] }
    }
    private var isMini: Bool { dockLayout == .compact }

    var body: some View {
        MediaDockFace(title: snapshot?.title ?? (enabledSources.isEmpty ? "No players" : "Nothing playing"), artist: snapshot?.artist,
                      artwork: activeSource.flatMap { monitor.artwork[$0] }, isPlaying: snapshot?.isPlaying ?? false)
        .frame(width: contentWidth, height: 54)
        .help(snapshot.map { "\($0.title) · \($0.artist) · \(activeSource?.title ?? "Now Playing")" }
            ?? (enabledSources.isEmpty ? "No players enabled · Open Now Playing to configure" : "Open Now Playing to connect to an enabled player"))
        .accessibilityLabel(snapshot.map { "Now Playing: \($0.title), by \($0.artist)" }
            ?? (enabledSources.isEmpty ? "Now Playing. No players enabled." : "Now Playing. No track information."))
        .onAppear(perform: synchronizeSubscriptions)
        .onDisappear {
            subscriptionIDs.values.forEach(monitor.unsubscribe)
            subscriptionIDs.removeAll()
        }
        .onChange(of: configuration.nowPlayingEnabledSources) { _ in synchronizeSubscriptions() }
    }

    private func synchronizeSubscriptions() {
        for source in Array(subscriptionIDs.keys) where !enabledSources.contains(source) {
            if let id = subscriptionIDs.removeValue(forKey: source) { monitor.unsubscribe(id) }
        }
        for source in enabledSources where subscriptionIDs[source] == nil {
            let id = UUID()
            subscriptionIDs[source] = id
            monitor.subscribe(id, to: source, kind: .compact)
        }
    }
}

private struct NowPlayingPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var subscriptionIDs: [NowPlayingSource: UUID] = [:]
    /// Players and controls sit behind a final disclosure; it starts open only when no player is enabled.
    @State private var settingsExpanded = false
    /// Why the last settings change was not kept, for example while saving is disabled.
    @State private var settingsError: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var preferredSource: NowPlayingSource { configuration.nowPlayingSource }
    private var skipSeconds: Int { configuration.nowPlayingSkipSeconds }
    private var hideWhenClosed: Bool { configuration.nowPlayingHidesWhenClosed }
    private var showsTrackControls: Bool { configuration.nowPlayingShowsTrackControls }
    private var showsSeekControls: Bool { configuration.nowPlayingShowsSeekControls }
    private var enabledSources: Set<NowPlayingSource> { Set(configuration.nowPlayingEnabledSources) }
    private var activeSource: NowPlayingSource? {
        #if DEBUG
        if let fixture = NowPlayingQAFixture.override { return fixture.source }
        #endif
        return NowPlayingSourcePolicy.activeSource(preferred: preferredSource,
                                                   enabledSources: enabledSources,
                                                   snapshots: monitor.snapshots)
    }
    private var source: NowPlayingSource { activeSource ?? preferredSource }
    private var layout: NowPlayingLayout { configuration.nowPlayingLayout }
    private var snapshot: NowPlayingSnapshot? {
        #if DEBUG
        if let fixture = NowPlayingQAFixture.override { return fixture.snapshot }
        #endif
        return activeSource.flatMap { monitor.snapshots[$0] }
    }
    private var errorMessage: String? {
        #if DEBUG
        if NowPlayingQAFixture.override != nil { return nil }
        #endif
        return activeSource.flatMap { monitor.errors[$0] }
    }
    private var runningSources: Set<NowPlayingSource> {
        #if DEBUG
        if let running = NowPlayingQAFixture.runningSources { return running }
        #endif
        return monitor.runningSources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            if enabledSources.isEmpty {
                GroupedSection {
                    GroupedRow("No players enabled", subtitle: "Turn on Apple Music or Spotify in Settings below.",
                               symbol: "music.note", color: .gray)
                }
            } else if let snapshot {
                trackDetails(snapshot)
                playbackControls(snapshot)
            } else {
                let installed = playerAppURL != nil
                GroupedSection {
                    GroupedRow(errorMessage == nil ? "Nothing is playing" : "Player access needs attention",
                               subtitle: errorMessage == nil
                                   ? (installed ? "Start something in \(source.title) to control it here." : "\(source.title) is not installed on this Mac.")
                                   : nil,
                               symbol: errorMessage == nil ? "music.note" : "exclamationmark.triangle.fill",
                               color: errorMessage == nil ? .gray : WidgetPalette.warning)
                    if installed {
                        GroupedRow("Open \(source.title)", role: .button, action: openPlayer)
                    }
                    if errorMessage != nil {
                        GroupedRow("Open Automation Settings", role: .button) { WidgetPrivacySettings.open(WidgetPrivacySettings.automation) }
                    }
                }
            }

            if let errorMessage {
                WidgetPopoutCaption(errorMessage, color: WidgetPalette.warning)
            }

            WidgetPopoutSettingsDisclosure(summary: enabledSources.isEmpty ? "No players" : nil, isExpanded: $settingsExpanded) {
                GroupedSection("Players", separatorInset: DockDesign.Grouped.separatorInset) {
                    ForEach(NowPlayingSource.allCases) { option in
                        let running = runningSources.contains(option)
                        GroupedRow(option.title, subtitle: running ? "Open" : "Closed",
                                   symbol: option == .appleMusic ? "music.note" : "headphones",
                                   color: running ? WidgetPalette.positive : .gray, isOn: enabledSourceBinding(for: option))
                            .help("\(option.title) is \(running ? "open" : "closed")")
                    }
                    GroupedRow("Preferred when paused") {
                        Picker("Preferred when paused", selection: setting(\.nowPlayingSource)) {
                            ForEach(NowPlayingSource.allCases.filter(enabledSources.contains)) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden().fixedSize()
                        .disabled(enabledSources.count < 2)
                        .accessibilityLabel("Preferred when paused")
                    }
                }

                GroupedSection("Controls",
                               footer: hideWhenClosed ? "The tile returns when an enabled player opens." : nil,
                               separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    GroupedRow("Popover") {
                        Picker("Popover controls", selection: setting(\.nowPlayingLayout)) {
                            ForEach(NowPlayingLayout.allCases) { option in Text(option.title).tag(option) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .accessibilityLabel("Popover controls")
                    }
                    GroupedRow("Show previous/next controls", isOn: setting(\.nowPlayingShowsTrackControls))
                    GroupedRow("Show seek controls", isOn: setting(\.nowPlayingShowsSeekControls))
                    if showsSeekControls {
                        WidgetStepperRow(title: "Seek interval", value: "\(skipSeconds) sec",
                                         amount: Binding(get: { skipSeconds },
                                                         set: { value in updateConfiguration { $0.nowPlayingSkipSeconds = min(max(value, 5), 60) } }),
                                         range: 5...60, step: 5)
                    }
                    GroupedRow("Hide tile when all enabled players are closed", isOn: setting(\.nowPlayingHidesWhenClosed))
                        .help("If the tile is hidden because every enabled player is closed, change this in Manage Docks.")
                }
                if let settingsError { WidgetPopoutCaption(settingsError, color: WidgetPalette.warning) }
            }
        }
        .onAppear {
            if enabledSources.isEmpty { settingsExpanded = true }
            synchronizeSubscriptions()
        }
        .onDisappear {
            subscriptionIDs.values.forEach(monitor.unsubscribe)
            subscriptionIDs.removeAll()
        }
        .onChange(of: item.widgetConfiguration?.nowPlayingEnabledSources) { _ in synchronizeSubscriptions() }
    }

    /// A setting read from and written straight to the saved configuration: no local copy to keep in sync.
    private func setting<Value>(_ keyPath: WritableKeyPath<WidgetConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] },
                set: { value in updateConfiguration { $0[keyPath: keyPath] = value } })
    }

    private func synchronizeSubscriptions() {
        for source in Array(subscriptionIDs.keys) where !enabledSources.contains(source) {
            if let id = subscriptionIDs.removeValue(forKey: source) { monitor.unsubscribe(id) }
        }
        for source in enabledSources where subscriptionIDs[source] == nil {
            let id = UUID()
            subscriptionIDs[source] = id
            monitor.subscribe(id, to: source, kind: .popout)
        }
        if !enabledSources.contains(preferredSource), let fallback = NowPlayingSource.allCases.first(where: enabledSources.contains) {
            updateConfiguration { $0.nowPlayingSource = fallback }
        }
    }

    private func enabledSourceBinding(for source: NowPlayingSource) -> Binding<Bool> {
        Binding(get: { enabledSources.contains(source) }, set: { isEnabled in
            var updated = enabledSources
            if isEnabled { updated.insert(source) }
            else { updated.remove(source) }
            let orderedSources = NowPlayingSource.allCases.filter(updated.contains)
            updateConfiguration { configuration in
                configuration.nowPlayingEnabledSources = orderedSources
                if !updated.contains(configuration.nowPlayingSource), let fallback = orderedSources.first {
                    configuration.nowPlayingSource = fallback
                }
            }
        })
    }

    /// Artwork, then title and artist; the album and a single-weight progress line in the full layout.
    private func trackDetails(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Group {
                    if let artwork = monitor.artwork[source] {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text(snapshot.artist).font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .help(snapshot.artist).accessibilityLabel("Artist: \(snapshot.artist)")
                    // One quiet line: the album (full layout) and the player.
                    let showsAlbum = layout == .full && !snapshot.album.isEmpty
                    Text(showsAlbum ? snapshot.album + " · " + source.title : source.title)
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                        .help(showsAlbum ? snapshot.album : source.title)
                        .accessibilityLabel(showsAlbum ? "Album: \(snapshot.album), playback source: \(source.title)" : "Playback source: \(source.title)")
                }
                Spacer(minLength: 0)
            }
            if layout == .full {
                if ticksPosition(snapshot) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        progressLine(snapshot, position: NowPlayingPresentation.position(snapshot, now: context.date))
                    }
                } else {
                    progressLine(snapshot, position: snapshot.position)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// Render QA keeps its fixed position, so captures do not depend on when they run.
    private func ticksPosition(_ snapshot: NowPlayingSnapshot) -> Bool {
        #if DEBUG
        if NowPlayingQAFixture.override != nil { return false }
        #endif
        return snapshot.isPlaying
    }

    private func progressLine(_ snapshot: NowPlayingSnapshot, position: TimeInterval) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.7))
                            .frame(width: geometry.size.width * NowPlayingPresentation.progress(position: position, duration: snapshot.duration))
                    }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(NowPlayingPresentation.timeString(position)) of \(NowPlayingPresentation.timeString(snapshot.duration))")
            HStack {
                Text(NowPlayingPresentation.timeString(position))
                Spacer()
                Text(NowPlayingPresentation.timeString(snapshot.duration))
            }
            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func playbackControls(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 18) {
            if showsSeekControls {
                Button { perform(.seekBackward(TimeInterval(skipSeconds))) } label: {
                    Label("Back \(skipSeconds) seconds", systemImage: NowPlayingPresentation.seekSymbol(forward: false, seconds: skipSeconds))
                }
                .buttonStyle(NowPlayingControlStyle())
                .help("Seek backward \(skipSeconds) seconds")
            }
            if showsTrackControls {
                Button { perform(.previousTrack) } label: { Label("Previous track", systemImage: "backward.end.fill") }
                    .buttonStyle(NowPlayingControlStyle())
                    .help("Previous track")
            }
            Button { perform(.togglePlayback) } label: {
                Label(snapshot.isPlaying ? "Pause" : "Play", systemImage: snapshot.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(NowPlayingControlStyle(prominent: true)).help(snapshot.isPlaying ? "Pause" : "Play")
            if showsTrackControls {
                Button { perform(.nextTrack) } label: { Label("Next track", systemImage: "forward.end.fill") }
                    .buttonStyle(NowPlayingControlStyle())
                    .help("Next track")
            }
            if showsSeekControls {
                Button { perform(.seekForward(TimeInterval(skipSeconds))) } label: {
                    Label("Forward \(skipSeconds) seconds", systemImage: NowPlayingPresentation.seekSymbol(forward: true, seconds: skipSeconds))
                }
                .buttonStyle(NowPlayingControlStyle())
                .help("Seek forward \(skipSeconds) seconds")
            }
        }
        .labelStyle(.iconOnly)
        .frame(maxWidth: .infinity)
    }

    private func perform(_ command: NowPlayingCommand) {
        monitor.perform(command, source: source)
    }

    private var playerAppURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) }

    /// Launching a player is a native effect, so isolated validation sessions never do it.
    private func openPlayer() {
        guard AppRuntimeEnvironment.allowsNativeEffects, let url = playerAppURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// A rejected change leaves the setting as it was, and says why.
    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        settingsError = WidgetConfigurationLookup.rejection(store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update))
    }
}

/// Player controls: quiet glyph circles, with a larger filled play/pause circle.
private struct NowPlayingControlStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { ControlBody(configuration: configuration, prominent: prominent) }
    private struct ControlBody: View {
        let configuration: ButtonStyle.Configuration
        var prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @DockAccessibilityStyle() private var accessibility
        @State private var hovered = false
        private var diameter: CGFloat { prominent ? 52 : 38 }
        var body: some View {
            configuration.label
                .font(.system(size: prominent ? 20 : 15, weight: .semibold))
                .foregroundStyle(prominent ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(prominent ? Color.primary : Color.primary.opacity(hovered ? 0.10 : 0.06)))
                .overlay(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0)))
                .overlay {
                    if accessibility.contrast == .increased && !prominent {
                        Circle().strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}
