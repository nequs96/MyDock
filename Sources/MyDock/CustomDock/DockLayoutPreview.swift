import SwiftUI
import AppKit

/// Uses live surface geometry with inert samples. Longer layouts scroll inside
/// the available preview space rather than stretching a short Dock to fill it, unless
/// `fitsByScale` asks for the whole Dock scaled down to fit (thumbnails of a finished Dock).
/// Only a live preview observes running apps, windows and media; a sample preview never redraws for them.
struct DockLayoutPreview: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    var maximumSideLength: CGFloat = 240
    var usesLiveData = false
    var fitsByScale = false

    var body: some View {
        if usesLiveData {
            LiveDockLayoutPreview(store: store, profile: profile, maximumSideLength: maximumSideLength, fitsByScale: fitsByScale)
        } else {
            DockLayoutPreviewFrame(store: store, profile: profile, maximumSideLength: maximumSideLength, fitsByScale: fitsByScale,
                                   usesLiveData: false, unpinnedRunningApplications: [], windows: [],
                                   runningMediaSources: Set(NowPlayingSource.allCases))
        }
    }
}

/// The live preview: running apps, windows and media sources from this Mac.
private struct LiveDockLayoutPreview: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    var maximumSideLength: CGFloat
    var fitsByScale: Bool
    @State private var applications: [DockItem] = []
    /// Created once on appear, not on every struct initialisation.
    @State private var runningAppCache: DockRunningAppCache?
    @ObservedObject private var windows = WindowAccessibilityMonitor.shared
    @ObservedObject private var media = NowPlayingMonitor.shared

    var body: some View {
        DockLayoutPreviewFrame(store: store, profile: profile, maximumSideLength: maximumSideLength, fitsByScale: fitsByScale,
                               usesLiveData: true,
                               unpinnedRunningApplications: runningAppCache?.matches(runtime: applications, profileItems: profile.items).unpinnedRuntime ?? [],
                               windows: windows.windows, runningMediaSources: media.runningSources)
            .onAppear {
                if runningAppCache == nil { runningAppCache = DockRunningAppCache(resolve: { AppLauncher.resolvedURL(for: $0) }) }
                applications = RuntimeDockApplications.items()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
                applications = RuntimeDockApplications.items()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
                applications = RuntimeDockApplications.items()
            }
    }
}

/// Lays out one preview from already-resolved runtime inputs.
private struct DockLayoutPreviewFrame: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    var maximumSideLength: CGFloat
    var fitsByScale: Bool
    var usesLiveData: Bool
    var unpinnedRunningApplications: [DockItem]
    var windows: [DockWindowDescriptor]
    var runningMediaSources: Set<NowPlayingSource>

    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    private var scale: CGFloat { CGFloat(settings.customDockSize) }
    private var horizontal: Bool { settings.customDockPosition == .bottom }
    private var crossLength: CGFloat { DockSurfaceMetrics.crossLength(settings: settings, scale: scale) }
    private var length: CGFloat {
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: unpinnedRunningApplications,
                                    windows: windows, runningMediaSources: runningMediaSources)
        // Previews end at their last tile (no trailing grip slot), like `CustomDockView` draws them.
        return max(100, DockSeparatorPolicy.previewContentLength(model.entries, settings: settings, scale: scale)
                   + 2 * DockSurfaceMetrics.padding(settings: settings, scale: scale))
    }

    var body: some View {
        let contentLength = length
        GeometryReader { geometry in
            let available = horizontal ? max(100, geometry.size.width - 20) : maximumSideLength
            let fit = DockPreviewFit.scale(contentLength: contentLength, available: available, fitsByScale: fitsByScale)
            let laidOutLength = fitsByScale ? contentLength : min(contentLength, available)
            CustomDockView(store: store, profile: profile, isPreview: true, usesLivePreviewData: usesLiveData)
                .environment(\.dockModuleRadius, DockSurfaceMetrics.moduleRadius(settings: settings, scale: scale))
                .frame(width: horizontal ? laidOutLength : crossLength, height: horizontal ? crossLength : laidOutLength)
                .scaleEffect(fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: (horizontal ? crossLength : min(contentLength, maximumSideLength)) + 20)
    }
}

/// A fitted preview shows the whole Dock without overflow controls, scaled down only when needed.
enum DockPreviewFit {
    static func scale(contentLength: CGFloat, available: CGFloat, fitsByScale: Bool) -> CGFloat {
        guard fitsByScale, contentLength.isFinite, available.isFinite, contentLength > available, available > 0 else { return 1 }
        return available / contentLength
    }
}
