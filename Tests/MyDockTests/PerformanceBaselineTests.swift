import Foundation
import Testing
@testable import MyDock

@MainActor
struct PerformanceBaselineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_PERFORMANCE_OUTPUT"] != nil))
    func recordComparableGeometryAndWriterScenarios() throws {
        let clock = ContinuousClock()
        func elapsed(_ start: ContinuousClock.Instant) -> Double {
            let c = start.duration(to: clock.now).components
            return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
        }
        var results: [[String: Any]] = []
        for count in [7, 30, 60] {
            let items = (0..<count).map { index in DockItem.widget(WidgetRegistry.all[index % WidgetRegistry.all.count].name) }
            let profile = DockProfile(name: "Synthetic", kind: .custom, items: items)
            var settings = AppSettings(); settings.showTrash = true
            var samples: [Double] = []
            for _ in 0..<30 {
                let start = clock.now
                for _ in 0..<100 {
                    let model = DockRenderModel(profile: profile, settings: settings, runningApplications: [], windows: [], runningMediaSources: [])
                    _ = model.contentLength(settings: settings, scale: 1)
                }
                samples.append(elapsed(start) / 100)
            }
            samples.sort()
            results.append(["scenario": "geometry-\(count)-widgets", "samples": samples.count,
                            "median_ms": samples[samples.count / 2], "p95_ms": samples[Int(Double(samples.count - 1) * 0.95)]])
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = PersistentState(profiles: (0..<50).map { index in
            DockProfile(name: "Profile \(index)", kind: .custom, items: (0..<40).map { _ in DockItem.widget("Clock") })
        })
        let writer = RevisionedStateWriter()
        let start = clock.now
        try writer.writeImmediately(state, to: folder.appendingPathComponent("state.json"), revision: 1)
        results.append(["scenario": "encode-atomic-write-50-profiles-2000-items", "elapsed_ms": elapsed(start)])
        var appearanceState = state
        let immediateStart = clock.now
        for index in 0..<20 {
            appearanceState.settings.customDockSize = 0.8 + Double(index) * 0.02
            try writer.writeImmediately(appearanceState, to: folder.appendingPathComponent("state.json"), revision: UInt64(100 + index))
        }
        results.append(["scenario": "20-appearance-updates-immediate-2000-items", "elapsed_ms": elapsed(immediateStart)])
        let coalescedStart = clock.now
        for index in 0..<20 {
            appearanceState.settings.customDockSize = 0.8 + Double(index) * 0.02
            writer.write(appearanceState, to: folder.appendingPathComponent("state.json"), revision: UInt64(200 + index)) { _ in }
        }
        try writer.writeImmediately(appearanceState, to: folder.appendingPathComponent("state.json"), revision: 220)
        results.append(["scenario": "20-appearance-updates-coalesced-with-flush-2000-items", "elapsed_ms": elapsed(coalescedStart)])
        let report: [String: Any] = ["recorded_at": Date.now.ISO8601Format(), "build": "SwiftPM test Debug",
                                   "macos": ProcessInfo.processInfo.operatingSystemVersionString, "processors": ProcessInfo.processInfo.processorCount,
                                   "iterations_per_geometry_sample": 100, "results": results,
                                   "limits": "Synthetic CPU/disk baseline. No network, native Dock mutation, energy, animation FPS, or OS acceptance claim."]
        let path = try #require(ProcessInfo.processInfo.environment["MYDOCK_PERFORMANCE_OUTPUT"])
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
