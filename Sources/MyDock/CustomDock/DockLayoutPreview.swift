import SwiftUI
import AppKit

/// Uses live surface geometry with inert samples. Longer layouts scroll inside
/// the available preview space rather than stretching a short Dock to fill it, unless
/// `fitsByScale` asks for the whole Dock scaled down to fit (thumbnails of a finished Dock).
struct DockLayoutPreview: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    var maximumSideLength: CGFloat = 240
    var usesLiveData = false
    var fitsByScale = false
    @State private var applications: [DockItem] = []
    @State private var runningAppCache = DockRunningAppCache(resolve: { AppLauncher.resolvedURL(for: $0) })
    @ObservedObject private var windows = WindowAccessibilityMonitor.shared
    @ObservedObject private var media = NowPlayingMonitor.shared

    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    private var scale: CGFloat { CGFloat(settings.customDockSize) }
    private var horizontal: Bool { settings.customDockPosition == .bottom }
    private var crossLength: CGFloat { DockSurfaceMetrics.crossLength(settings: settings, scale: scale) }
    private var length: CGFloat {
        let unpinned = usesLiveData ? runningAppCache.matches(runtime: applications, profileItems: profile.items).unpinnedRuntime : []
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: unpinned,
                                    windows: usesLiveData ? windows.windows : [],
                                    runningMediaSources: usesLiveData ? media.runningSources : Set(NowPlayingSource.allCases))
        // Previews end at their last tile (no trailing grip slot), like `CustomDockView` draws them.
        return max(100, DockSeparatorPolicy.previewContentLength(model.entries, settings: settings, scale: scale)
                   + 2 * DockSurfaceMetrics.padding(settings: settings, scale: scale))
    }

    var body: some View {
        GeometryReader { geometry in
            let length = length
            let available = horizontal ? max(100, geometry.size.width - 20) : maximumSideLength
            let fit = DockPreviewFit.scale(contentLength: length, available: available, fitsByScale: fitsByScale)
            let laidOutLength = fitsByScale ? length : min(length, available)
            CustomDockView(store: store, profile: profile, isPreview: true, usesLivePreviewData: usesLiveData)
                .environment(\.dockModuleRadius, DockSurfaceMetrics.moduleRadius(settings: settings, scale: scale))
                .frame(width: horizontal ? laidOutLength : crossLength, height: horizontal ? crossLength : laidOutLength)
                .scaleEffect(fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: (horizontal ? crossLength : min(length, maximumSideLength)) + 20)
        .onAppear { if usesLiveData { applications = RuntimeDockApplications.items() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            if usesLiveData { applications = RuntimeDockApplications.items() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            if usesLiveData { applications = RuntimeDockApplications.items() }
        }
    }
}

/// A fitted preview shows the whole Dock without overflow controls, scaled down only when needed.
enum DockPreviewFit {
    static func scale(contentLength: CGFloat, available: CGFloat, fitsByScale: Bool) -> CGFloat {
        guard fitsByScale, contentLength.isFinite, available.isFinite, contentLength > available, available > 0 else { return 1 }
        return available / contentLength
    }
}
