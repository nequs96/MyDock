import SwiftUI
import AppKit

/// Uses live surface geometry with inert samples. Longer layouts scroll inside
/// the available preview space rather than stretching a short Dock to fill it.
struct DockLayoutPreview: View {
    @ObservedObject var store: ProfileStore
    var profile: DockProfile
    var maximumSideLength: CGFloat = 240
    var usesLiveData = false
    @State private var applications: [DockItem] = []
    @ObservedObject private var windows = WindowAccessibilityMonitor.shared
    @ObservedObject private var media = NowPlayingMonitor.shared

    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    private var scale: CGFloat { CGFloat(settings.customDockSize) }
    private var horizontal: Bool { settings.customDockPosition == .bottom }
    private var crossLength: CGFloat { DockSurfaceMetrics.crossLength(settings: settings, scale: scale) }
    private var length: CGFloat {
        let model = DockRenderModel(profile: profile, settings: settings, runningApplications: usesLiveData ? applications : [],
                                    windows: usesLiveData ? windows.windows : [],
                                    runningMediaSources: usesLiveData ? media.runningSources : Set(NowPlayingSource.allCases))
        return max(100, model.contentLength(settings: settings, scale: scale) + 2 * DockSurfaceMetrics.padding(settings: settings, scale: scale))
    }

    var body: some View {
        GeometryReader { geometry in
            CustomDockView(store: store, profile: profile, isPreview: true, usesLivePreviewData: usesLiveData)
                .environment(\.dockModuleRadius, DockSurfaceMetrics.moduleRadius(settings: settings, scale: scale))
                .frame(width: horizontal ? min(length, max(100, geometry.size.width - 20)) : crossLength,
                       height: horizontal ? crossLength : min(length, maximumSideLength))
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
