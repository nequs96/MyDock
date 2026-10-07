import AppKit
import Combine
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MyDock

@MainActor
struct DockAuditRegressionTests {
    @Test func resizePreviewDoesNotPublishOrPersistProfileChangesUntilDragEnds() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom)
        let file = directory.appendingPathComponent("state.json")
        let original = try Data(contentsOf: file)
        var statePublications = 0
        let observation = store.$state.dropFirst().sink { _ in statePublications += 1 }
        for sample in 0..<200 { store.previewDockSize(0.65 + Double(sample) / 250, for: id) }
        #expect(statePublications == 0)
        #expect(!store.isSaving)
        #expect(try Data(contentsOf: file) == original)
        #expect(store.state.settings.customDockSize == 1)
        #expect(abs(store.effectiveSettings(profileID: id).customDockSize - 1.446) < 0.000001)
        store.finishDockResize(for: id)
        #expect(statePublications == 1)
        #expect(store.dockResizePreview == nil)
        #expect(abs(ProfileStore(fileURL: file, allowsSystemChanges: false).state.settings.customDockSize - 1.446) < 0.000001)
        withExtendedLifetime(observation) {}
    }

    @Test func resizePreviewKeepsProfileScopeAndRejectsInvalidSamples() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try store.createProfileAndPersist(kind: .custom)
        let other = try store.createProfileAndPersist(kind: .custom)
        store.setAppearance(ProfileAppearance(settings: store.state.settings), for: local)
        store.previewDockSize(1.3, for: local)
        store.previewDockSize(.nan, for: local)
        store.previewDockSize(2, for: local)
        #expect(store.effectiveSettings(profileID: local).customDockSize == 1.3)
        #expect(store.effectiveSettings(profileID: other).customDockSize == 1)
        store.finishDockResize(for: other)
        #expect(store.dockResizePreview?.profileID == local)
        store.finishDockResize(for: local)
        #expect(store.state.settings.customDockSize == 1)
        #expect(store.effectiveSettings(profileID: local).customDockSize == 1.3)
    }

    @Test func glassOpacityAndMotionMigrateAndRoundTripWithoutResettingAppearance() throws {
        var settings = AppSettings()
        settings.customDockGlassOpacity = 0.62
        settings.dockAnimationsEnabled = false
        settings.dockAnimationStyle = .grow
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileAppearance(settings: settings))) as? [String: Any])
        legacy.removeValue(forKey: "glassOpacity")
        let migrated = try JSONDecoder().decode(ProfileAppearance.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.applying(to: settings).customDockGlassOpacity == 0)
        #expect(migrated.material == settings.customDockMaterial)
        let bounded = try JSONDecoder().decode(AppSettings.self, from: Data("{\"customDockGlassOpacity\":2,\"dockAnimationStyle\":\"future-style\"}".utf8))
        #expect(bounded.customDockGlassOpacity == 1)
        #expect(bounded.dockAnimationsEnabled)
        #expect(bounded.dockAnimationStyle == .slide)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(empty.customDockGlassOpacity == 0)
        var invalid = ProfileAppearance(settings: settings); invalid.glassOpacity = .infinity
        #expect(throws: ProfileValidationError.self) { try invalid.validate() }
    }

    @Test func dockMotionRespectsOffAndReduceMotionWithDistinctRevealGeometry() {
        let frame = NSRect(x: 100, y: 50, width: 500, height: 98)
        for position in DockPosition.allCases {
            #expect(DockPanelMotion.transitionFrame(from: frame, position: position, style: .fade) == frame)
            #expect(DockPanelMotion.transitionFrame(from: frame, position: position, style: .slide) == DockPanelMotion.hiddenFrame(from: frame, position: position))
            #expect(DockPanelMotion.transitionFrame(from: frame, position: position, style: .grow) == frame)
            #expect(DockPanelMotion.scale(visible: false, style: .grow) < 1)
            #expect(DockPanelMotion.scale(visible: true, style: .grow) == 1)
        }
        #expect(DockPanelMotion.duration(visible: true, enabled: false, reduceMotion: false) == 0)
        #expect(DockPanelMotion.duration(visible: false, enabled: true, reduceMotion: true) == 0)
        #expect(DockPanelMotion.duration(visible: true, enabled: true, reduceMotion: false) > 0)
    }
    @Test func profileMorphSharesSemanticTilesWithoutCollidingWithRepeatedItems() {
        var app = DockItem.application(at: URL(fileURLWithPath: "/Applications/Example.app"))
        app.bundleIdentifier = "app.example"
        var copiedApp = app
        copiedApp.id = UUID()
        let clock = DockItem.widget("Clock")
        var copiedClock = clock
        copiedClock.id = UUID()
        let first = DockVisualIdentity.items([app, clock, copiedApp])
        let second = DockVisualIdentity.items([copiedClock, copiedApp, app])
        #expect(first[0].id == second[1].id)
        #expect(first[1].id == second[0].id)
        #expect(first[2].id == second[2].id)
        #expect(Set(first.map(\.id)).count == 3)
        #expect(first[0].item.id != second[1].item.id)
    }

    @Test func statusDistinguishesRememberedRunningAndAppliedProfiles() {
        let custom = DockProfile(name: "Custom", kind: .custom)
        let native = DockProfile(name: "Native", kind: .native)
        var settings = AppSettings()
        settings.activeCustomProfileID = custom.id
        settings.activeNativeProfileID = native.id
        settings.setupMode = .nativeOnly
        #expect(DockProfileStatus(profile: custom, settings: settings) == .inactive)
        #expect(DockProfileStatus.preferredWorkspaceProfileID(profiles: [custom, native], settings: settings) == native.id)
        #expect(DockProfileStatus(profile: native, settings: settings) == .applied(hidden: false))
        settings.setupMode = .both
        #expect(DockProfileStatus(profile: custom, settings: settings) == .active)
        #expect(DockProfileStatus.preferredWorkspaceProfileID(profiles: [native, custom], settings: settings) == custom.id)
        settings.setupMode = .customMain
        let hidden = DockProfileStatus(profile: native, settings: settings)
        #expect(hidden == .applied(hidden: true))
        #expect(!hidden.showsActiveIndicator)
        settings.activeCustomProfileID = nil
        #expect(DockProfileStatus(profile: custom, settings: settings) == .inactive)
    }

    @Test func nativePasteboardPreservesGroupAndURLOrderAndRejectsMalformedPayloads() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let payload = DockDragPayload(profileID: UUID(), itemIDs: [UUID(), UUID()])
        board.setData(try JSONEncoder().encode(payload), forType: DockCanvasPasteboard.itemsType)
        guard case .items(let decoded) = try #require(DockCanvasPasteboard.values(from: board).first) else { Issue.record("Missing item payload"); return }
        #expect(decoded.profileID == payload.profileID)
        #expect(decoded.itemIDs == payload.itemIDs)
        board.clearContents()
        board.setData(Data("invalid-json".utf8), forType: DockCanvasPasteboard.itemsType)
        #expect(DockCanvasPasteboard.values(from: board).isEmpty)
        let urls = [URL(fileURLWithPath: "/tmp/first.txt"), URL(fileURLWithPath: "/tmp/second.txt")]
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
        #expect(DockCanvasPasteboard.values(from: board).compactMap { if case .url(let url) = $0 { return url }; return nil } == urls)
    }

    /// Calls only an isolated NSView's event handlers; sends no desktop events,
    /// opens no window and changes no production profiles or native preferences.
    @Test func pointerReorderDeliversEndGroupAndSpacerAndCancelsOutsideOrChangedProfile() throws {
        let items = [DockItem.widget("Clock"), DockItem.widget("Weather"), DockItem.spacer(.small), DockItem.widget("Focus Timer")]
        let view = DockCanvasDragView(frame: CGRect(x: 0, y: 0, width: 400, height: 80))
        view.items = items
        view.itemFrames = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, CGRect(x: $0 * 100, y: 0, width: 80, height: 80)) })
        var drops: [(DockDragPayload, UUID?)] = []
        var selected: [UUID] = []
        view.selectItem = { id, command, shift in
            #expect(!command && !shift)
            selected.append(id)
        }
        view.applyDrop = { values, target in
            if case .items(let payload) = values.first { drops.append((payload, target)); return true }
            return false
        }
        func event(_ type: NSEvent.EventType, _ x: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 40), modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func drag(_ from: CGFloat, _ to: CGFloat) throws {
            view.mouseDown(with: try event(.leftMouseDown, from))
            view.mouseDragged(with: try event(.leftMouseDragged, to))
            view.mouseUp(with: try event(.leftMouseUp, to))
        }
        try drag(40, 380)
        #expect(drops.count == 1)
        #expect(drops[0].0.itemIDs == [items[0].id])
        #expect(drops[0].1 == nil)
        #expect(selected == [items[0].id])
        view.selection = Set(items.prefix(2).map(\.id))
        try drag(140, 380)
        #expect(drops.last?.0.itemIDs == items.prefix(2).map(\.id))
        #expect(drops.last?.1 == nil)
        #expect(selected == [items[0].id])
        view.selection = []
        try drag(240, 90)
        #expect(drops.last?.0.itemIDs == [items[2].id])
        #expect(drops.last?.1 == items[1].id)
        #expect(selected == [items[0].id, items[2].id])
        let count = drops.count
        try drag(40, 440)
        #expect(drops.count == count)
        #expect(selected == [items[0].id, items[2].id])
        view.mouseDown(with: try event(.leftMouseDown, 40))
        view.mouseDragged(with: try event(.leftMouseDragged, 380))
        view.profileID = UUID()
        view.mouseUp(with: try event(.leftMouseUp, 380))
        #expect(drops.count == count)
        view.mouseDown(with: try event(.leftMouseDown, 40))
        view.mouseDragged(with: try event(.leftMouseDragged, 380))
        view.cancelOperation(nil)
        view.mouseUp(with: try event(.leftMouseUp, 380))
        #expect(drops.count == count)
    }

    @Test func keyboardSelectionUsesItsEndpointAndRecoversFromRemovedItems() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        #expect(DockItemSelectionPolicy.next(in: ids, selected: [], cursor: nil, forward: true) == ids[0])
        #expect(DockItemSelectionPolicy.next(in: ids, selected: [], cursor: nil, forward: false) == ids[3])
        let range = DockItemSelectionPolicy.range(in: ids, from: ids[0], to: ids[2])
        let contracted = DockItemSelectionPolicy.next(in: ids, selected: range, cursor: ids[2], forward: false)
        #expect(contracted == ids[1])
        #expect(DockItemSelectionPolicy.range(in: ids, from: ids[0], to: contracted!) == Set(ids.prefix(2)))
        #expect(DockItemSelectionPolicy.next(in: Array(ids.dropFirst(2)), selected: range, cursor: ids[1], forward: true) == ids[3])
        #expect(DockItemSelectionPolicy.next(in: [UUID](), selected: range, cursor: ids[2], forward: true) == nil)
    }

    private func fixture() -> (ProfileStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false), directory)
    }

    @Test func pinningTheSameRuntimeItemInDifferentProfilesPersistsUniqueIdentities() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try store.createProfileAndPersist(kind: .custom, name: "First")
        let second = try store.createProfileAndPersist(kind: .custom, name: "Second")
        var item = DockItem.application(at: URL(fileURLWithPath: "/Applications/Example.app"))
        item.id = RuntimeDockIdentity.uuid("running:app.example")
        store.add(item, to: first)
        store.insert(item, before: nil, in: second)
        store.add(DockRenderModel.systemTrash, to: first)
        store.add(DockRenderModel.systemTrash, to: second)
        store.flush()
        try ProfileSemanticValidator.validate(store.state.profiles)
        #expect(!store.hasUnpersistedChanges)
        let restored = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        #expect(restored.state.profiles.map { $0.items.count } == [2, 2])
        let ids = restored.state.profiles.flatMap { $0.items.map(\.id) }
        #expect(Set(ids).count == 4)
    }

    @Test func deletingAProfileRemovesItsUnsavableDraft() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom)
        var draft = DockProfileDraft(profile: try #require(store.activeCustomProfile))
        draft.update { $0.name = "Unsaved draft" }
        store.editSessions.set(draft, for: id)
        store.deleteProfile(id)
        #expect(store.editSessions.drafts[id] == nil)
        #expect(!store.editSessions.hasUnsavedChanges)
        try store.editSessions.saveAll()
    }

    @Test func directResizeKeepsProfileOverridesAndGlobalInheritanceSeparate() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try store.createProfileAndPersist(kind: .custom, name: "Local")
        let inherited = try store.createProfileAndPersist(kind: .custom, name: "Inherited")
        var appearance = ProfileAppearance(settings: store.state.settings)
        appearance.size = 0.8
        appearance.material = .dark
        store.setAppearance(appearance, for: local)
        store.setDockSize(1.2, for: local)
        #expect(store.isSaving)
        #expect(store.effectiveSettings(profileID: local).customDockSize == 1.2)
        #expect(store.state.settings.customDockSize == 1)
        store.setDockSize(0.9, for: inherited)
        #expect(store.state.settings.customDockSize == 0.9)
        #expect(store.effectiveSettings(profileID: local).customDockSize == 1.2)
        store.setDockSize(.nan, for: local)
        store.setDockSize(10, for: inherited)
        store.flush()
        let restored = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        #expect(restored.effectiveSettings(profileID: local).customDockSize == 1.2)
        #expect(restored.effectiveSettings(profileID: local).customDockMaterial == .dark)
        #expect(restored.effectiveSettings(profileID: inherited).customDockSize == 0.9)
        #expect(!restored.hasUnpersistedChanges)
    }

    @Test func savedProfileStateIsPrivateToItsOwner() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = store.createProfile(kind: .custom)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("state.json").path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o777 == 0o600)
    }

    @Test func nativeRecoveryJournalIsPrivateAndRejectsOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transaction.json")
        let journal = FileDockTransactionJournal(fileURL: file)
        try journal.begin(snapshot: [["tile-type": "spacer-tile"]], profileID: UUID())
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o777 == 0o600)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(BackupManager.maximumArchiveBytes + 1))
        try handle.close()
        #expect(throws: NativeDockError.self) { try journal.pendingSnapshot() }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func sharedRefreshFailureIsPublishedOnce() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom)
        let first = DockItem.widget("AI Limits"), second = DockItem.widget("AI Limits")
        store.add(first, to: id)
        store.add(second, to: id)
        var loads = 0
        let gate = AuditLaneIGate()
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in
            loads += 1
            await gate.hold()
            throw AuditProviderError.unavailable
        }
        var failuresPublished = 0
        let observation = coordinator.$errors.sink { if !$0.isEmpty { failuresPublished += 1 } }
        defer { observation.cancel() }
        // The first refresh owns the request; the second joins it while the loader is held.
        let a = Task { await coordinator.refresh(item: first, profileID: id) }
        let started = await gate.waitForStart()
        #expect(started)
        let b = Task { await coordinator.refresh(item: second, profileID: id) }
        await Task.yield()
        await gate.release()
        await a.value; await b.value
        #expect(loads == 1)
        #expect(failuresPublished == 1)
        #expect(coordinator.refreshing.isEmpty)
    }

    @Test func cancelledWindowCaptureCannotOverwriteAReenabledCapture() async throws {
        let (_, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let window = previewWindow(title: "Document")
        let gate = AuditCaptureGate()
        let monitor = WindowAccessibilityMonitor(
            previewCache: WindowPreviewDiskCache(directoryURL: directory), sampleWindows: { [window] },
            captureWindows: { _, _ in await gate.capture() }, canCapture: { true })
        defer { monitor.setEnabled(false) }
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { gate.count == 1 }
        monitor.setEnabled(false)
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { gate.count == 2 }
        gate.finish(1, windowID: window.id, width: 10)
        try await Task.sleep(for: .milliseconds(30))
        #expect(monitor.previews.isEmpty)
        gate.finish(2, windowID: window.id, width: 20)
        try await waitUntil { monitor.previews[window.id] != nil }
        #expect(monitor.previews[window.id]?.size.width == 20)
    }

    @Test func changingAWindowTitleInvalidatesItsOldPreview() async throws {
        let (_, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var window = previewWindow(title: "Old document")
        let gate = AuditCaptureGate()
        let monitor = WindowAccessibilityMonitor(
            previewCache: WindowPreviewDiskCache(directoryURL: directory), sampleWindows: { [window] },
            captureWindows: { _, _ in await gate.capture() }, canCapture: { true })
        defer { monitor.setEnabled(false) }
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { gate.count == 1 }
        gate.finish(1, windowID: window.id, width: 10)
        try await waitUntil { monitor.previews[window.id] != nil }
        window.title = "New document"
        monitor.refresh()
        try await waitUntil { monitor.windows.first?.title == "New document" }
        #expect(monitor.previews[window.id] == nil)
    }

    @Test func windowCaptureChecksPermissionAgainBeforePublishing() async throws {
        let (_, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let window = previewWindow(title: "Document")
        var allowed = true
        let gate = AuditCaptureGate()
        let monitor = WindowAccessibilityMonitor(
            previewCache: WindowPreviewDiskCache(directoryURL: directory), sampleWindows: { [window] },
            captureWindows: { _, _ in await gate.capture() }, canCapture: { allowed })
        defer { monitor.setEnabled(false) }
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { gate.count == 1 }
        allowed = false
        gate.finish(1, windowID: window.id, width: 10)
        try await Task.sleep(for: .milliseconds(30))
        #expect(monitor.previews.isEmpty)
    }

    @Test func hiddenTimersFinishAfterClockOrWakeReconciliation() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hidden = try store.createProfileAndPersist(kind: .custom, name: "Hidden")
        let focus = DockItem.widget("Focus Timer"), countdown = DockItem.widget("Countdown")
        store.add(focus, to: hidden)
        store.add(countdown, to: hidden)
        var now = Date.now
        store.updateWidgetConfiguration(itemID: focus.id, in: hidden) { $0.startFocusTimer(at: now) }
        store.updateWidgetConfiguration(itemID: countdown.id, in: hidden) { $0.startCountdown(at: now) }
        _ = store.createProfile(kind: .custom, name: "Visible")
        let coordinator = WidgetLifecycleCoordinator(store: store, now: { now })
        coordinator.rescheduleTimers()
        now = now.addingTimeInterval(24 * 60 * 60)
        coordinator.rescheduleTimers()
        try await waitUntil {
            let items = store.state.profiles.first { $0.id == hidden }?.items ?? []
            return items.first { $0.id == focus.id }?.widgetConfiguration?.focusStartedAt == nil &&
                items.first { $0.id == countdown.id }?.widgetConfiguration?.countdownStartedAt == nil
        }
        let configuration = try #require(store.state.profiles.first { $0.id == hidden }?.items.first?.widgetConfiguration)
        #expect(configuration.focusElapsedBeforeStart == Double(configuration.focusDurationSeconds))
    }

    @Test func failedAutoHideReenablePreservesTheOriginalRestoreRecord() async throws {
        let defaults = ValidationDefaults()
        let backend = AuditAutoHideBackend()
        let relauncher = AuditRelauncher()
        let controller = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        try await controller.setCustomDockMain(true)
        // An external preference change differs from the original false value.
        backend.value = nil
        relauncher.failingCalls = [2]
        do {
            try await controller.setCustomDockMain(true)
            Issue.record("The re-enable failure should be reported")
        } catch {}
        #expect(backend.value == nil)
        #expect(controller.hasPendingRestore)
        try await controller.restoreBeforeExit()
        #expect(backend.value == false)
        #expect(backend.settings.revealDelay == nil)
        #expect(backend.settings.noBouncing == nil)
        #expect(!controller.hasPendingRestore)
    }

    @Test func failedReplacementRestartRollsBackEveryOwnedPreference() async throws {
        let defaults = ValidationDefaults()
        let backend = AuditAutoHideBackend()
        backend.settings = NativeDockVisibilitySettings(autoHide: false, revealDelay: 0.4, noBouncing: false)
        let original = backend.settings
        let relauncher = AuditRelauncher()
        relauncher.failingCalls = [1]
        let controller = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        do {
            try await controller.setCustomDockMain(true)
            Issue.record("The failed Dock restart must be reported")
        } catch {}
        #expect(backend.settings == original)
        #expect(!controller.hasPendingRestore)
        #expect(relauncher.calls == 2)
        #expect(controller.errorMessage != nil)
    }

    @Test func cancellingAQueuedNativeApplyDoesNotWriteDockPreferences() async throws {
        let gate = DockSystemOperationGate()
        await gate.acquire()
        let backend = AuditDockBackend()
        let relauncher = AuditRelauncher()
        let controller = NativeDockController(backend: backend, relauncher: relauncher,
                                              journal: AuditDockJournal(), gate: gate)
        let profile = DockProfile(name: "Cancelled", kind: .native, items: [.spacer(.small)])
        var started = false
        let task = Task { started = true; try await controller.apply(profile) }
        do { try await waitUntil { started } }
        catch { task.cancel(); await gate.release(); throw error }
        task.cancel()
        await gate.release()
        do {
            try await task.value
            Issue.record("A cancelled apply must return cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(backend.writes == 0)
        #expect(relauncher.calls == 0)
        #expect(controller.health == .ready)
    }

    /// S07-004: cancelling an apply after the new layout was written still restores the previous Dock and leaves
    /// no journal behind, instead of failing the rollback in the cancelled task.
    @Test func cancellingAnApplyDuringTheRelaunchStillRestoresThePreviousDock() async throws {
        let backend = AuditDockBackend()
        let original: [[String: Any]] = [["tile-type": "spacer-tile"]]
        backend.tiles = original
        let relauncher = CancellationSensitiveRelauncher()
        let journal = AuditDockJournal()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: journal,
                                              gate: DockSystemOperationGate())
        let profile = DockProfile(name: "Interrupted", kind: .native, items: [.spacer(.small)])
        let task = Task { try await controller.apply(profile) }
        do { try await waitUntil { relauncher.calls == 1 } }
        catch { task.cancel(); throw error }
        task.cancel()
        do {
            try await task.value
            Issue.record("A cancelled apply must report its cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, original))
        #expect(relauncher.calls == 2)
        #expect(journal.snapshot == nil)
        #expect(controller.health == .ready)
    }

    /// S07-005: launch recovery restores only while the Dock still shows the interrupted change. A Dock changed
    /// since is left for Restore Previous Dock, and one already back on the earlier layout just loses the journal.
    @Test func launchRecoveryNeverOverwritesADockChangedSinceTheInterruption() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before: [[String: Any]] = [["tile-type": "spacer-tile"]]
        let interrupted: [[String: Any]] = [["tile-type": "small-spacer-tile"]]
        let backend = AuditDockBackend()
        let relauncher = AuditRelauncher()

        let changed = FileDockTransactionJournal(fileURL: folder.appendingPathComponent("changed.json"))
        try changed.begin(snapshot: before, target: interrupted, profileID: UUID())
        backend.tiles = [["tile-type": "spacer-tile"], ["tile-type": "small-spacer-tile"]]
        let first = NativeDockController(backend: backend, relauncher: relauncher, journal: changed, gate: DockSystemOperationGate())
        try await first.recoverInterruptedTransaction(automatic: true)
        #expect(first.health == .recoveryRequired && first.recoveryError != nil)
        #expect(backend.writes == 0 && relauncher.calls == 0)
        #expect(try changed.pendingSnapshot() != nil)
        try await first.recoverInterruptedTransaction()
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, before) && first.health == .ready)

        let showing = FileDockTransactionJournal(fileURL: folder.appendingPathComponent("showing.json"))
        try showing.begin(snapshot: before, target: interrupted, profileID: UUID())
        backend.tiles = interrupted
        let second = NativeDockController(backend: backend, relauncher: relauncher, journal: showing, gate: DockSystemOperationGate())
        try await second.recoverInterruptedTransaction(automatic: true)
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, before) && second.health == .ready)
        #expect(try showing.pendingSnapshot() == nil)

        let undone = FileDockTransactionJournal(fileURL: folder.appendingPathComponent("undone.json"))
        try undone.begin(snapshot: before, target: interrupted, profileID: UUID())
        let restarts = relauncher.calls, writes = backend.writes
        let third = NativeDockController(backend: backend, relauncher: relauncher, journal: undone, gate: DockSystemOperationGate())
        try await third.recoverInterruptedTransaction(automatic: true)
        #expect(relauncher.calls == restarts && backend.writes == writes && third.health == .ready)
        #expect(try undone.pendingSnapshot() == nil)
    }

    @Test func nativeAutoSaveRetainsErrorsAndRetriesFailedDiskWrites() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = try store.createProfileAndPersist(kind: .native)
        store.updateSettings { $0.automaticallySaveNativeDockChanges = true }
        let backend = AuditDockBackend()
        let controller = NativeDockController(backend: backend, relauncher: AuditRelauncher(), journal: AuditDockJournal())
        let monitor = NativeDockAutoSaveMonitor(store: store, controller: controller, backend: backend, pollingInterval: nil)
        monitor.configure(enabled: true, profileID: profile)
        await monitor.refreshNow()
        let file = directory.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        backend.tiles = [["tile-type": "small-spacer-tile"]]
        await monitor.refreshNow()
        #expect(monitor.errorMessage != nil)
        #expect(store.hasUnpersistedChanges)
        await monitor.refreshNow()
        #expect(monitor.errorMessage != nil)
        try FileManager.default.removeItem(at: file)
        await monitor.refreshNow()
        #expect(monitor.errorMessage == nil)
        #expect(!store.hasUnpersistedChanges)
        let restored = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(restored.nativeProfiles.first?.items.first?.spacerKind == .small)
    }

    private func previewWindow(title: String) -> DockWindowDescriptor {
        DockWindowDescriptor(processID: 42, windowIndex: 0, bundleIdentifier: "app.example", applicationName: "Example",
                             title: title, isMinimized: false, accessibilityIdentifier: "stable-window")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}

private enum AuditProviderError: Error { case unavailable }

@MainActor
private final class AuditAutoHideBackend: DockAutoHidePreferencesBackend {
    var settings = NativeDockVisibilitySettings(autoHide: false, revealDelay: nil, noBouncing: nil)
    var value: Bool? {
        get { settings.autoHide }
        set { settings.autoHide = newValue }
    }
    func readVisibilitySettings() throws -> NativeDockVisibilitySettings { settings }
    func writeVisibilitySettings(_ settings: NativeDockVisibilitySettings) throws { self.settings = settings }
}

@MainActor
private final class AuditRelauncher: DockRelaunching {
    var calls = 0
    var failingCalls = Set<Int>()
    func restartDock() async throws {
        calls += 1
        if failingCalls.contains(calls) { throw AuditProviderError.unavailable }
    }
}

/// Behaves like `killall` under `BoundedSubprocessCapture.runCancellable`: a relaunch in a cancelled task stops at once.
/// The first relaunch waits until the apply is cancelled.
@MainActor
private final class CancellationSensitiveRelauncher: DockRelaunching {
    var calls = 0
    func restartDock() async throws {
        calls += 1
        if calls == 1 { try await Task.sleep(for: .seconds(60)) }
        try Task.checkCancellation()
    }
}

@MainActor
private final class AuditDockBackend: DockPreferencesBackend {
    var tiles: [[String: Any]] = []
    var writes = 0
    func readCurrentTiles() throws -> [[String: Any]] { tiles }
    func writeTiles(_ tiles: [[String: Any]]) throws { writes += 1; self.tiles = tiles }
}

@MainActor
private final class AuditDockJournal: DockTransactionJournal {
    var snapshot: [[String: Any]]?
    func begin(snapshot: [[String: Any]], profileID: UUID) throws { self.snapshot = snapshot }
    func pendingSnapshot() throws -> [[String: Any]]? { snapshot }
    func clear() throws { snapshot = nil }
}

@MainActor
private final class AuditCaptureGate {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<WindowPreviewBatch, Never>] = [:]
    func capture() async -> WindowPreviewBatch {
        count += 1
        let id = count
        return await withCheckedContinuation { pending[id] = $0 }
    }
    func finish(_ id: Int, windowID: String, width: CGFloat) {
        pending.removeValue(forKey: id)?.resume(returning: WindowPreviewBatch(
            images: [windowID: NSImage(size: NSSize(width: width, height: width))], attemptedIDs: [windowID]))
    }
    deinit { pending.values.forEach { $0.resume(returning: WindowPreviewBatch()) } }
}
