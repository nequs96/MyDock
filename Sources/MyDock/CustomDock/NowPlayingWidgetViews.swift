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

private struct NowPlayingCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @Environment(\.widgetLayout) private var dockLayout
    var item: DockItem
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var subscriptionIDs: [NowPlayingSource: UUID] = [:]

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var enabledSources: Set<NowPlayingSource> { Set(configuration.nowPlayingEnabledSources) }
    private var activeSource: NowPlayingSource? {
        NowPlayingSourcePolicy.activeSource(preferred: configuration.nowPlayingSource,
                                            enabledSources: enabledSources,
                                            snapshots: monitor.snapshots)
    }
    private var snapshot: NowPlayingSnapshot? { activeSource.flatMap { monitor.snapshots[$0] } }
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
    @State private var sourceSelection = NowPlayingSource.appleMusic.rawValue
    @State private var layoutSelection = NowPlayingLayout.full.rawValue
    @State private var skipSeconds = 15
    @State private var hideWhenClosed = false
    @State private var showsTrackControls = true
    @State private var showsSeekControls = true
    @State private var subscriptionIDs: [NowPlayingSource: UUID] = [:]

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var preferredSource: NowPlayingSource { NowPlayingSource(rawValue: sourceSelection) ?? .appleMusic }
    private var enabledSources: Set<NowPlayingSource> { Set(configuration.nowPlayingEnabledSources) }
    private var activeSource: NowPlayingSource? {
        NowPlayingSourcePolicy.activeSource(preferred: preferredSource,
                                            enabledSources: enabledSources,
                                            snapshots: monitor.snapshots)
    }
    private var source: NowPlayingSource { activeSource ?? preferredSource }
    private var layout: NowPlayingLayout { NowPlayingLayout(rawValue: layoutSelection) ?? .full }
    private var snapshot: NowPlayingSnapshot? { activeSource.flatMap { monitor.snapshots[$0] } }
    private var errorMessage: String? { activeSource.flatMap { monitor.errors[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Preferred when paused", selection: $sourceSelection) {
                    ForEach(NowPlayingSource.allCases.filter(enabledSources.contains)) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .frame(maxWidth: 190)
                .disabled(enabledSources.count < 2)
                Spacer()
                Picker("Popover controls", selection: $layoutSelection) {
                    ForEach(NowPlayingLayout.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .labelsHidden().frame(maxWidth: 90)
            }

            HStack(spacing: 12) {
                ForEach(NowPlayingSource.allCases) { option in
                    Toggle(isOn: enabledSourceBinding(for: option)) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(monitor.runningSources.contains(option) ? Color.green : Color.secondary.opacity(0.55))
                                .frame(width: 6, height: 6)
                            Text("\(option.title) · \(monitor.runningSources.contains(option) ? "Open" : "Closed")")
                        }
                    }
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("\(option.title) is \(monitor.runningSources.contains(option) ? "open" : "closed")")
                }
            }

            if enabledSources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("No players enabled").font(.callout.weight(.medium))
                    Text("Enable Apple Music or Spotify to show and control playback.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else if let snapshot {
                trackDetails(snapshot)
                playbackControls(snapshot)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(errorMessage == nil ? "Nothing is playing" : "Player access needs attention")
                        .font(.callout.weight(.medium))
                    Button("Open \(source.title)", action: openPlayer)
                        .buttonStyle(DockButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if showsSeekControls {
                HStack {
                    Text("Seek interval").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Stepper("\(skipSeconds) sec", value: $skipSeconds, in: 5...60, step: 5)
                        .font(.caption).frame(maxWidth: 150)
                }
            }
            Toggle("Show previous/next controls", isOn: $showsTrackControls).font(.caption)
            Toggle("Show seek controls", isOn: $showsSeekControls).font(.caption)
            Toggle("Hide tile when all enabled players are closed", isOn: $hideWhenClosed)
                .font(.caption)
            if hideWhenClosed {
                Text("The tile reappears when any enabled player opens. If all players are closed, use Manage Docks to change this setting.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
        .frame(width: 350)
        .onAppear {
            sourceSelection = configuration.nowPlayingSource.rawValue
            layoutSelection = configuration.nowPlayingLayout.rawValue
            skipSeconds = configuration.nowPlayingSkipSeconds
            hideWhenClosed = configuration.nowPlayingHidesWhenClosed
            showsTrackControls = configuration.nowPlayingShowsTrackControls
            showsSeekControls = configuration.nowPlayingShowsSeekControls
            synchronizeSubscriptions()
        }
        .onDisappear {
            subscriptionIDs.values.forEach(monitor.unsubscribe)
            subscriptionIDs.removeAll()
        }
        .onChange(of: sourceSelection) { rawValue in
            guard let value = NowPlayingSource(rawValue: rawValue) else { return }
            updateConfiguration { $0.nowPlayingSource = value }
        }
        .onChange(of: layoutSelection) { rawValue in
            guard let value = NowPlayingLayout(rawValue: rawValue) else { return }
            updateConfiguration { $0.nowPlayingLayout = value }
        }
        .onChange(of: skipSeconds) { value in
            updateConfiguration { $0.nowPlayingSkipSeconds = min(max(value, 5), 60) }
        }
        .onChange(of: hideWhenClosed) { value in
            updateConfiguration { $0.nowPlayingHidesWhenClosed = value }
        }
        .onChange(of: showsTrackControls) { value in
            updateConfiguration { $0.nowPlayingShowsTrackControls = value }
        }
        .onChange(of: showsSeekControls) { value in
            updateConfiguration { $0.nowPlayingShowsSeekControls = value }
        }
        .onChange(of: item.widgetConfiguration?.nowPlayingEnabledSources) { _ in synchronizeSubscriptions() }
        .onChange(of: item.widgetConfiguration?.nowPlayingSource) { value in sourceSelection = (value ?? .appleMusic).rawValue }
        .onChange(of: item.widgetConfiguration?.nowPlayingLayout) { value in layoutSelection = (value ?? .full).rawValue }
        .onChange(of: item.widgetConfiguration?.nowPlayingSkipSeconds) { value in skipSeconds = value ?? 15 }
        .onChange(of: item.widgetConfiguration?.nowPlayingHidesWhenClosed) { value in hideWhenClosed = value ?? false }
        .onChange(of: item.widgetConfiguration?.nowPlayingShowsTrackControls) { value in showsTrackControls = value ?? true }
        .onChange(of: item.widgetConfiguration?.nowPlayingShowsSeekControls) { value in showsSeekControls = value ?? true }
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
            sourceSelection = fallback.rawValue
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

    private func trackDetails(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if let artwork = monitor.artwork[source] {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
                            .overlay(Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title).font(.headline).lineLimit(2)
                    Text(snapshot.artist).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .help(snapshot.artist).accessibilityLabel("Artist: \(snapshot.artist)")
                    if layout == .full, !snapshot.album.isEmpty {
                        Text(snapshot.album).font(.caption).foregroundStyle(.tertiary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .help(snapshot.album).accessibilityLabel("Album: \(snapshot.album)")
                    }
                }
                Spacer(minLength: 0)
            }

            if layout == .full {
                ProgressView(value: min(snapshot.position, max(snapshot.duration, 1)), total: max(snapshot.duration, 1))
                HStack {
                    Text(timeString(snapshot.position))
                    Spacer()
                    Text(timeString(snapshot.duration))
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }

    private func playbackControls(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 14) {
            if showsSeekControls {
                Button { perform(.seekBackward(TimeInterval(skipSeconds))) } label: {
                    Label("Back \(skipSeconds) seconds", systemImage: "gobackward")
                }
                .help("Seek backward \(skipSeconds) seconds")
            }
            if showsTrackControls {
                Button { perform(.previousTrack) } label: { Image(systemName: "backward.end.fill") }
                    .help("Previous track")
            }
            Button { perform(.togglePlayback) } label: {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 38, height: 34)
            }
            .buttonStyle(DockButtonStyle(primary: true)).help(snapshot.isPlaying ? "Pause" : "Play")
            if showsTrackControls {
                Button { perform(.nextTrack) } label: { Image(systemName: "forward.end.fill") }
                    .help("Next track")
            }
            if showsSeekControls {
                Button { perform(.seekForward(TimeInterval(skipSeconds))) } label: {
                    Label("Forward \(skipSeconds) seconds", systemImage: "goforward")
                }
                .help("Seek forward \(skipSeconds) seconds")
            }
        }
        .labelStyle(.iconOnly)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private func perform(_ command: NowPlayingCommand) {
        monitor.perform(command, source: source)
    }

    private func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
