import AppKit
import SwiftUI
import Testing
@testable import MyDock

/// FX-02: cached running-app matching, side-Dock badge placement, separators only between content,
/// one Dock colour-scheme source, editor reorder settle and fitted Dock previews.
@MainActor
struct FX02Tests {
    private func app(_ path: String, _ bundle: String) -> DockItem {
        var item = DockItem.application(at: URL(fileURLWithPath: path))
        item.bundleIdentifier = bundle
        return item
    }

    private func runtime(_ path: String, _ bundle: String) -> DockItem {
        var item = app(path, bundle)
        item.id = RuntimeDockIdentity.uuid("running:" + bundle + "|" + path)
        return item
    }

    // MARK: Codex #7: running-app matches are cached

    @Test func cacheNormalizesOnlyWhenRunningOrPinnedAppsChange() {
        var normalizations = 0
        var resolutions = 0
        let cache = DockRunningAppCache(normalize: { normalizations += 1; return $0.standardizedFileURL },
                                        resolve: { _ in resolutions += 1; return nil })
        let safari = app("/Applications/Safari.app", "com.apple.Safari")
        let mail = app("/Applications/Mail.app", "com.apple.mail")
        var items = [safari, mail, DockItem.widget("Clock")]
        let running = [runtime("/Applications/Safari.app", "com.apple.Safari"), runtime("/Applications/Notes.app", "com.apple.Notes")]

        let first = cache.matches(runtime: running, profileItems: items)
        #expect(first.runningPinnedItemIDs == [safari.id])
        #expect(first.unpinnedRuntime.map(\.bundleIdentifier) == ["com.apple.Notes"])
        let afterFirst = normalizations
        #expect(afterFirst > 0)
        #expect(cache.computations == 1)

        // Hover and magnification re-render the body with the same inputs: no file-system work.
        for _ in 0..<50 { #expect(cache.matches(runtime: running, profileItems: items) == first) }
        #expect(normalizations == afterFirst)
        #expect(cache.computations == 1)

        // A widget edit leaves the pinned apps unchanged.
        items[2].title = "World Clock"
        _ = cache.matches(runtime: running, profileItems: items)
        #expect(cache.computations == 1)

        // A launch or a pinned-app change recomputes once.
        _ = cache.matches(runtime: running + [runtime("/Applications/Mail.app", "com.apple.mail")], profileItems: items)
        #expect(cache.computations == 2)
        items.removeFirst()
        let afterUnpin = cache.matches(runtime: running + [runtime("/Applications/Mail.app", "com.apple.mail")], profileItems: items)
        #expect(cache.computations == 3)
        #expect(afterUnpin.runningPinnedItemIDs == [mail.id])
        #expect(Set(afterUnpin.unpinnedRuntime.compactMap(\.bundleIdentifier)) == ["com.apple.Safari", "com.apple.Notes"])
        // Every saved copy matched or its bundle was not running: the resolver never ran.
        #expect(resolutions == 0)
    }

    @Test func relocatedCopyResolvesOnlyWhenItsBundleIsRunning() {
        var resolutions = 0
        var moved = app("/Volumes/Old/Safari.app", "com.apple.Safari")
        moved.title = "Safari"
        let idle = app("/Volumes/Old/Mail.app", "com.apple.mail")
        let matches = DockRunningAppMatches.compute(
            runtime: [runtime("/Applications/Safari.app", "com.apple.Safari")], profileItems: [moved, idle],
            normalize: { $0.standardizedFileURL },
            resolve: { item in resolutions += 1; return item.bundleIdentifier == "com.apple.Safari" ? URL(fileURLWithPath: "/Applications/Safari.app") : nil })
        #expect(matches.runningPinnedItemIDs == [moved.id])
        // The running relocated copy is the pinned app, not a second runtime tile.
        #expect(matches.unpinnedRuntime.isEmpty)
        #expect(resolutions == 1)

        let none = DockRunningAppMatches.compute(runtime: [], profileItems: [moved, idle], normalize: { _ in
            Issue.record("Nothing is running, so nothing is normalized"); return URL(fileURLWithPath: "/")
        }, resolve: { _ in nil })
        #expect(none == DockRunningAppMatches())
    }

    @Test func prematchedRenderModelEqualsTheDesignatedInitializer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FX02-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Pinned.app", "Other.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let pinned = app(root.appendingPathComponent("Pinned.app").path, "test.pinned")
        let profile = DockProfile(name: "FX02", kind: .custom, items: [pinned, .widget("Clock")])
        let running = [runtime(root.appendingPathComponent("Pinned.app").path, "test.pinned"),
                       runtime(root.appendingPathComponent("Other.app").path, "test.other")]
        for showRunning in [true, false] {
            for showTrash in [true, false] {
                var settings = AppSettings()
                settings.showRunningApps = showRunning
                settings.showTrash = showTrash
                let expected = DockRenderModel(profile: profile, settings: settings, runningApplications: running, windows: [],
                                               runningMediaSources: [])
                let matches = DockRunningAppMatches.compute(runtime: running, profileItems: profile.items,
                                                            normalize: InstalledApplicationIdentity.normalizedURL, resolve: { _ in nil })
                let cached = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: matches.unpinnedRuntime,
                                             windows: [], runningMediaSources: [])
                #expect(cached.entries.map(\.id) == expected.entries.map(\.id))
            }
        }
    }

    @Test func dockBodyNoLongerNormalizesOnEveryEvaluation() throws {
        // Source guard: the view body reads the cache rather than normalizing per evaluation.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MyDock/DockManagement/CustomDockView.swift"), encoding: .utf8)
        #expect(!source.contains("InstalledApplicationIdentity.normalizedURL"))
        #expect(!source.contains("RuntimeDockApplications.pinnedURLs"))
        #expect(source.contains("runningAppCache.matches("))
    }

    // MARK: Separators only between content

    @Test func separatorsDrawOnlyBetweenContent() {
        let finder = app("/System/Library/CoreServices/Finder.app", "com.apple.finder")
        let clock = DockItem.widget("Clock")
        let other = runtime("/Applications/Notes.app", "com.apple.Notes")
        let trash = DockRenderModel.systemTrash
        let pinnedEnd = DockRenderEntry.insertion.id
        let windows = DockRenderEntry.boundary(.windows).id
        let running = DockRenderEntry.boundary(.running).id

        // Every QA Dock and preset preview: pinned items and nothing after them.
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .item(clock, pinned: true), .insertion]).isEmpty)
        // Trash or running apps follow: the pinned-end line shows.
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .insertion, .item(trash, pinned: false)]) == [pinnedEnd])
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .insertion, .boundary(.running),
                                                         .item(other, pinned: false)]) == [pinnedEnd])
        // Running apps on with none running: the line still needs something after it.
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .insertion, .boundary(.running)]).isEmpty)
        // Nothing pinned: no line before the first tile.
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.insertion, .boundary(.running), .item(other, pinned: false)]).isEmpty)
        // A spacer is an invisible gap, not content.
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(.spacer(.regular), pinned: true), .insertion, .item(trash, pinned: false)]).isEmpty)
        // Never two lines in a row; the running boundary never draws.
        let window = DockWindowDescriptor(processID: 42, windowIndex: 0, bundleIdentifier: "app.example", applicationName: "Example",
                                          title: "Draft", isMinimized: true, accessibilityIdentifier: nil)
        let ids = DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .insertion, .boundary(.running),
                                                           .boundary(.windows), .window(window)])
        #expect(ids == [pinnedEnd])
        #expect(!ids.contains(running))
        #expect(DockSeparatorPolicy.visibleSeparatorIDs([.item(finder, pinned: true), .insertion, .item(other, pinned: false),
                                                         .boundary(.windows), .window(window)]) == [pinnedEnd, windows])
    }

    @Test func defaultRenderModelsEndWithoutALine() {
        var settings = AppSettings()
        settings.showRunningApps = false
        settings.showTrash = false
        let profile = DockProfile(name: "Preset", kind: .custom, items: [.widget("Clock"), .widget("Battery")])
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                    runningMediaSources: [])
        #expect(DockSeparatorPolicy.visibleSeparatorIDs(model.entries).isEmpty)
        settings.showTrash = true
        let withTrash = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                        runningMediaSources: [])
        #expect(DockSeparatorPolicy.visibleSeparatorIDs(withTrash.entries) == [DockRenderEntry.insertion.id])
    }

    @Test func previewsEndAtTheirLastTile() {
        var settings = AppSettings()
        settings.showRunningApps = true
        settings.showTrash = false
        let scale: CGFloat = 1
        let profile = DockProfile(name: "Preset", kind: .custom, items: [.widget("Clock"), .widget("Battery")])
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                    runningMediaSources: [])
        // The pinned-end slot and the empty running boundary collapse in previews only.
        #expect(DockSeparatorPolicy.previewCollapsedEntryIDs(model.entries)
                == [DockRenderEntry.insertion.id, DockRenderEntry.boundary(.running).id])
        let collapsedLength = (14 + 5) * scale + 2 * CGFloat(settings.customDockItemSpacing) * scale
        #expect(abs(DockSeparatorPolicy.previewContentLength(model.entries, settings: settings, scale: scale)
                    - (model.contentLength(settings: settings, scale: scale) - collapsedLength)) < 0.001)
        // Trash closes the Dock: nothing collapses and the lengths agree.
        settings.showTrash = true
        settings.showRunningApps = false
        let withTrash = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                        runningMediaSources: [])
        #expect(DockSeparatorPolicy.previewCollapsedEntryIDs(withTrash.entries).isEmpty)
        #expect(DockSeparatorPolicy.previewContentLength(withTrash.entries, settings: settings, scale: scale)
                == withTrash.contentLength(settings: settings, scale: scale))
        // An empty Dock keeps its drop slot.
        settings.showTrash = false
        let empty = DockRenderModel(profile: DockProfile(name: "Empty", kind: .custom, items: []), settings: settings,
                                    unpinnedRunningApplications: [], windows: [], runningMediaSources: [])
        #expect(empty.entries.map(\.id) == [DockRenderEntry.insertion.id])
        #expect(DockSeparatorPolicy.previewCollapsedEntryIDs(empty.entries).isEmpty)
    }

    // MARK: D4: side-Dock badges

    @Test func sideDockBadgesStayInsideTheirColumn() {
        for scale in [CGFloat(0.65), 1, 1.5] {
            let tile = CGSize(width: 54 * scale, height: 54 * scale)
            for width in [16 * scale, 22 * scale, 30 * scale] {
                let badge = CGSize(width: width, height: 16 * scale)
                for position in [DockPosition.left, .right] {
                    let frame = DockBadgePlacement.frame(badgeSize: badge, tileSize: tile, position: position, scale: scale)
                    #expect(frame.minX >= 0 && frame.maxX <= tile.width && frame.minY >= 0 && frame.maxY <= tile.height)
                }
            }
            // The bottom Dock keeps the system-Dock overhang toward the top-trailing corner.
            #expect(DockBadgePlacement.offset(position: .bottom, scale: scale) == CGSize(width: 4 * scale, height: -2 * scale))
        }
    }

    // MARK: D18: one colour-scheme source

    @Test func dockSchemeFollowsThemeThenMaterialThenSystem() {
        #expect(DockColorSchemePolicy.scheme(theme: .dark, material: .solid, system: .light) == .dark)
        #expect(DockColorSchemePolicy.scheme(theme: .light, material: .dark, system: .dark) == .light)
        #expect(DockColorSchemePolicy.scheme(theme: .system, material: .dark, system: .light) == .dark)
        for material in CustomDockMaterial.allCases where material != .dark {
            #expect(DockColorSchemePolicy.scheme(theme: .system, material: material, system: .light) == .light)
            #expect(DockColorSchemePolicy.scheme(theme: .system, material: material, system: .dark) == .dark)
        }
        #expect(EnvironmentValues().dockSwatchTheme == .system)
    }

    // MARK: Editor reorder settle

    @Test func reorderSettlesOnlyTheMovedItems() {
        let ids = (0..<5).map { _ in UUID() }
        // ⌘→ on the second item.
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: [ids[0], ids[2], ids[1], ids[3], ids[4]], selection: [ids[1]]) == [ids[1]])
        // Without a selection the item outside the longest kept run settles.
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: [ids[4], ids[0], ids[1], ids[2], ids[3]]) == [ids[4]])
        // A multi-item move of the selection.
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: [ids[1], ids[3], ids[0], ids[2], ids[4]],
                                                   selection: [ids[1], ids[3]]) == [ids[1], ids[3]])
        // A selection that does not explain the move falls back to the order.
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: [ids[0], ids[1], ids[2], ids[4], ids[3]], selection: [ids[0]]).count == 1)
        // Unchanged, added or removed items never settle.
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: ids).isEmpty)
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: ids + [UUID()]).isEmpty)
        #expect(DockReorderSettlePolicy.movedItems(from: ids, to: Array(ids.dropLast())).isEmpty)
        // Reduce Motion: no settle animation and the scale rests at identity.
        #expect(DockMotionPolicy.settleAnimation(reduceMotion: true, animationsEnabled: true) == nil)
        #expect(DockMotionPolicy.settleScale(isSettling: true, reduceMotion: true) == 1)
        #expect(DockMotionPolicy.reorderAnimation(reduceMotion: true, animationsEnabled: true) == nil)
    }

    @Test func editorMovesUseTheDockReorderMotion() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MyDock/UI/DockCanvas.swift"), encoding: .utf8)
        #expect(!source.contains("Motion.transform"))
        #expect(source.contains("DockMotionPolicy.reorderAnimation"))
        #expect(source.contains("DockMotionPolicy.settleAnimation"))
    }

    // MARK: D17: fitted previews

    @Test func fittedPreviewScalesOnlyWhenTheDockOverflows() {
        #expect(DockPreviewFit.scale(contentLength: 700, available: 540, fitsByScale: true) == CGFloat(540) / 700)
        #expect(DockPreviewFit.scale(contentLength: 400, available: 540, fitsByScale: true) == 1)
        #expect(DockPreviewFit.scale(contentLength: 700, available: 540, fitsByScale: false) == 1)
        #expect(DockPreviewFit.scale(contentLength: .infinity, available: 540, fitsByScale: true) == 1)
    }
}

@Suite struct DockMissingTargetsTests {
    @Test func checksEachFileBackedItemOnceAndSkipsWidgetsAndSpacers() {
        let app = DockItem.application(at: URL(fileURLWithPath: "/Applications/Missing.app"))
        let present = DockItem.application(at: URL(fileURLWithPath: "/Applications/Safari.app"))
        let folder = DockItem(type: .folder, title: "Gone", url: URL(fileURLWithPath: "/Volumes/Old/Gone"))
        let items = [app, present, .widget("Clock"), .spacer(.small), folder]
        var checked: [UUID] = []
        let missing = DockMissingTargets.ids(in: items) { item in
            checked.append(item.id)
            return item.id != present.id
        }
        #expect(missing == [app.id, folder.id])
        #expect(checked == [app.id, present.id, folder.id])
    }
}
