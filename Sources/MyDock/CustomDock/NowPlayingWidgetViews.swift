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
    var item: DockItem
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var subscriptionID = UUID()

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: NowPlayingSnapshot? { monitor.snapshots[configuration.nowPlayingSource] }

    var body: some View {
        VStack(spacing: 2) {
            if let artwork = monitor.artwork[configuration.nowPlayingSource] {
                Image(nsImage: artwork).resizable().scaledToFill()
                    .frame(width: 31, height: 31).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: snapshot?.isPlaying == true ? "waveform" : "music.note")
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
            }
            Text(snapshot?.title ?? configuration.nowPlayingSource.title)
                .font(.system(size: 7, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: 50)
        }
        .frame(width: 54, height: 54)
        .help(snapshot.map { "\($0.title) · \($0.artist)" } ?? "Open Now Playing to connect to \(configuration.nowPlayingSource.title)")
        .onAppear { monitor.subscribe(subscriptionID, to: configuration.nowPlayingSource, kind: .compact) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
        .onChange(of: configuration.nowPlayingSource) { source in
            monitor.subscribe(subscriptionID, to: source, kind: .compact)
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
    @State private var subscriptionID = UUID()

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var source: NowPlayingSource { NowPlayingSource(rawValue: sourceSelection) ?? .appleMusic }
    private var layout: NowPlayingLayout { NowPlayingLayout(rawValue: layoutSelection) ?? .full }
    private var snapshot: NowPlayingSnapshot? { monitor.snapshots[source] }
    private var errorMessage: String? { monitor.errors[source] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Player", selection: $sourceSelection) {
                    ForEach(NowPlayingSource.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .labelsHidden().frame(maxWidth: 150)
                Spacer()
                Picker("Layout", selection: $layoutSelection) {
                    ForEach(NowPlayingLayout.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .labelsHidden().frame(maxWidth: 90)
            }

            if let snapshot {
                trackDetails(snapshot)
                playbackControls(snapshot)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(errorMessage == nil ? "Nothing is playing" : "Player access needs attention")
                        .font(.callout.weight(.medium))
                    Button("Open \(source.title)", action: openPlayer)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Seek interval").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper("\(skipSeconds) sec", value: $skipSeconds, in: 5...60, step: 5)
                    .font(.caption).frame(maxWidth: 150)
            }
            Toggle("Hide tile when \(source.title) is closed", isOn: $hideWhenClosed)
                .font(.caption)
            if hideWhenClosed {
                Text("The tile reappears when \(source.title) opens. Launch it from Applications to edit this setting again.")
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
            monitor.subscribe(subscriptionID, to: configuration.nowPlayingSource, kind: .popout)
        }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
        .onChange(of: sourceSelection) { rawValue in
            guard let value = NowPlayingSource(rawValue: rawValue) else { return }
            updateConfiguration { $0.nowPlayingSource = value }
            monitor.subscribe(subscriptionID, to: value, kind: .popout)
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
        .onChange(of: item.widgetConfiguration?.nowPlayingSource) { value in sourceSelection = (value ?? .appleMusic).rawValue }
        .onChange(of: item.widgetConfiguration?.nowPlayingLayout) { value in layoutSelection = (value ?? .full).rawValue }
        .onChange(of: item.widgetConfiguration?.nowPlayingSkipSeconds) { value in skipSeconds = value ?? 15 }
        .onChange(of: item.widgetConfiguration?.nowPlayingHidesWhenClosed) { value in hideWhenClosed = value ?? false }
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
                    Text(snapshot.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    if layout == .full, !snapshot.album.isEmpty {
                        Text(snapshot.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
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
            Button { perform(.seekBackward(TimeInterval(skipSeconds))) } label: {
                Label("Back \(skipSeconds) seconds", systemImage: "gobackward")
            }
            .help("Seek backward \(skipSeconds) seconds")
            Button { perform(.previousTrack) } label: { Image(systemName: "backward.end.fill") }
                .help("Previous track")
            Button { perform(.togglePlayback) } label: {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 38, height: 34)
            }
            .buttonStyle(.borderedProminent).help(snapshot.isPlaying ? "Pause" : "Play")
            Button { perform(.nextTrack) } label: { Image(systemName: "forward.end.fill") }
                .help("Next track")
            Button { perform(.seekForward(TimeInterval(skipSeconds))) } label: {
                Label("Forward \(skipSeconds) seconds", systemImage: "goforward")
            }
            .help("Seek forward \(skipSeconds) seconds")
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
