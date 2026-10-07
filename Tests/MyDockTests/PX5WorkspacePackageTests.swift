import Foundation
import Testing
@testable import MyDock

/// PX-5: OP-01 Start Workspace and OP-06 portable Dock package.
/// Native effects go through an injected launcher; files stay in temporary directories.
@MainActor
struct PX5WorkspacePackageTests {
    // MARK: Fixtures

    private func app(_ name: String) -> DockItem {
        DockItem(type: .application, title: name, url: URL(fileURLWithPath: "/nonexistent-px5/\(name).app"),
                 bundleIdentifier: "com.example.\(name.lowercased())")
    }

    private func folder(_ name: String) -> DockItem {
        DockItem.file(at: URL(fileURLWithPath: "/nonexistent-px5/\(name)", isDirectory: true), isFolder: true)
    }

    private func link(_ host: String) -> DockItem {
        DockItem.link(URL(string: "https://\(host)")!, title: host)
    }

    private func workspaceProfile() -> DockProfile {
        var profile = DockProfile(name: "Work", kind: .custom,
                                  items: [app("Mail"), .spacer(.small), folder("Project"), .widget("Clock"), link("example.com"), app("Notes")])
        // Chosen out of Dock order on purpose; targets always resolve in Dock order.
        profile.setWorkspaceItem(profile.items[5].id, included: true)
        profile.setWorkspaceItem(profile.items[0].id, included: true)
        profile.setWorkspaceItem(profile.items[4].id, included: true)
        profile.setWorkspaceItem(profile.items[2].id, included: true)
        return profile
    }

    private func temporaryStore() -> (ProfileStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("px5-" + UUID().uuidString)
        return (ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false), directory)
    }

    // MARK: Workspace persistence

    @Test func profilesWithoutAWorkspaceEncodeAndDecodeUnchanged() throws {
        let profile = DockProfile(name: "Old", kind: .custom, items: [app("Mail")])
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        #expect(!json.contains("workspace"))
        let old = """
        {"id":"\(UUID().uuidString)","name":"Old","kind":"custom","color":"blue","items":[],"createdAt":0}
        """
        let decoded = try JSONDecoder().decode(DockProfile.self, from: Data(old.utf8))
        #expect(decoded.workspace == nil)
        #expect(!decoded.hasWorkspace)
        #expect(decoded.workspaceTargets.isEmpty)
    }

    @Test func malformedWorkspaceDecodesLenientlyWithoutLosingTheProfile() throws {
        let itemID = UUID()
        let item = """
        {"id":"\(itemID.uuidString)","type":"application","title":"Mail","url":"file:///nonexistent-px5/Mail.app"}
        """
        for workspace in ["5", "\"text\"", "{\"itemIDs\":7}", "[]"] {
            let json = """
            {"id":"\(UUID().uuidString)","name":"Odd","kind":"custom","color":"blue","items":[\(item)],"createdAt":0,"workspace":\(workspace)}
            """
            let decoded = try JSONDecoder().decode(DockProfile.self, from: Data(json.utf8))
            #expect(decoded.items.count == 1, "\(workspace)")
            #expect(!decoded.hasWorkspace, "\(workspace)")
        }
        let partial = """
        {"id":"\(UUID().uuidString)","name":"Partial","kind":"custom","color":"blue","items":[\(item)],"createdAt":0,
         "workspace":{"itemIDs":["not-a-uuid","\(itemID.uuidString)","\(itemID.uuidString)"]}}
        """
        let decoded = try JSONDecoder().decode(DockProfile.self, from: Data(partial.utf8))
        #expect(decoded.workspace?.itemIDs == [itemID])
        #expect(decoded.workspaceTargets.map(\.id) == [itemID])
    }

    @Test func workspaceOnlyHoldsEligibleItemsInDockOrder() {
        var profile = workspaceProfile()
        #expect(profile.workspaceTargets.map(\.title) == ["Mail", "Project", "example.com", "Notes"])
        // Spacers and widgets never join.
        profile.setWorkspaceItem(profile.items[1].id, included: true)
        profile.setWorkspaceItem(profile.items[3].id, included: true)
        #expect(profile.workspaceTargets.count == 4)
        #expect(profile.workspaceCandidates.count == 4)
        // Removing an item keeps its reference for undo, but it no longer opens.
        let removed = profile.items.remove(at: 0)
        #expect(profile.isInWorkspace(removed.id))
        #expect(profile.workspaceTargets.map(\.title) == ["Project", "example.com", "Notes"])
        profile.items.insert(removed, at: 0)
        #expect(profile.workspaceTargets.first?.title == "Mail")
        // Clearing every choice returns to no workspace.
        for item in profile.items { profile.setWorkspaceItem(item.id, included: false) }
        #expect(profile.workspace == nil)
    }

    @Test func freshIdentitiesKeepTheWorkspaceSelection() throws {
        let profile = workspaceProfile()
        let copy = ProfileSanitizer.newIdentity(profile)
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: profile.items.map(\.id)))
        #expect(copy.workspaceTargets.map(\.title) == profile.workspaceTargets.map(\.title))
        #expect(copy.workspace?.itemIDs.allSatisfy { id in copy.items.contains { $0.id == id } } == true)

        let restored = try #require(BackupManager.readArchive(BackupManager.makeArchive(from: [profile])).importedProfiles.first)
        #expect(restored.workspaceTargets.map(\.title) == profile.workspaceTargets.map(\.title))
        let restoredIDs: Set<UUID> = Set(restored.workspace?.itemIDs ?? [])
        let originalIDs: [UUID] = profile.workspace?.itemIDs ?? []
        #expect(restoredIDs.isDisjoint(with: originalIDs))

        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfile(profile)
        let duplicateID = try store.duplicateProfile(id)
        let duplicate = try #require(store.state.profiles.first { $0.id == duplicateID })
        #expect(duplicate.workspaceTargets.map(\.title) == profile.workspaceTargets.map(\.title))
    }

    @Test func savingADraftKeepsTheWorkspaceEdit() throws {
        let profile = DockProfile(name: "Draft", kind: .custom, items: [app("Mail"), folder("Project")])
        var draft = DockProfileDraft(profile: profile)
        draft.update { $0.setWorkspaceItem(profile.items[1].id, included: true) }
        let merged = try draft.merged(with: profile)
        #expect(merged.workspaceTargets.map(\.title) == ["Project"])
    }

    // MARK: Start decision and outcomes

    @Test func onlyRunningApplicationsAreActivatedInsteadOfOpened() {
        #expect(WorkspaceStartPlan.action(for: app("Mail"), isMissing: false, isRunning: true) == .activate)
        #expect(WorkspaceStartPlan.action(for: app("Mail"), isMissing: false, isRunning: false) == .open)
        #expect(WorkspaceStartPlan.action(for: folder("P"), isMissing: false, isRunning: true) == .open)
        #expect(WorkspaceStartPlan.action(for: link("a.com"), isMissing: false, isRunning: true) == .open)
        #expect(WorkspaceStartPlan.action(for: app("Mail"), isMissing: true, isRunning: true) == .missing)
    }

    @Test func startOpensTargetsInOrderAndRecordsEachOutcome() async {
        let profile = workspaceProfile()
        let targets = profile.workspaceTargets
        let launcher = FakeWorkspaceLauncher()
        launcher.running = [targets[0].id]          // Mail is running
        launcher.missing = [targets[1].id]          // Project folder is missing
        launcher.failures = [targets[3].id: "Denied"] // Notes fails
        let run = WorkspaceStartRun(targets: targets, launcher: launcher)
        #expect(run.results.map(\.planned) == [.activate, .missing, .open, .open])
        #expect(run.phase == .preview)
        #expect(launcher.opened.isEmpty && launcher.activated.isEmpty)

        await run.start()
        #expect(run.phase == .finished)
        #expect(run.results.map(\.outcome) == [.alreadyRunning, .missing, .opened, .failed("Denied")])
        #expect(launcher.activated == [targets[0].id])
        #expect(launcher.opened == [targets[2].id, targets[3].id])
        // Starting again is a no-op; nothing reopens.
        await run.start()
        #expect(launcher.opened.count == 2)
    }

    @Test func anAppThatQuitBeforeActivationIsOpenedInstead() async {
        let target = app("Mail")
        let launcher = FakeWorkspaceLauncher()
        launcher.running = [target.id]
        launcher.activationSucceeds = false
        let run = WorkspaceStartRun(targets: [target], launcher: launcher)
        await run.start()
        #expect(run.results.first?.outcome == .opened)
        #expect(launcher.opened == [target.id])
    }

    @Test func cancelStopsTheRemainingTargetsWithoutClosingAnything() async {
        let targets = workspaceProfile().workspaceTargets
        let launcher = FakeWorkspaceLauncher()
        let run = WorkspaceStartRun(targets: targets, launcher: launcher)
        run.cancel() // Ignored before start.
        launcher.onOpen = { item in if item.id == targets[1].id { run.cancel() } }
        await run.start()
        #expect(run.phase == .cancelled)
        #expect(launcher.opened == [targets[0].id, targets[1].id])
        #expect(run.results.map(\.outcome) == [.opened, .opened, .cancelled, .cancelled])
    }

    @Test func locatingAMissingTargetOpensTheRepairedCopyOnce() async {
        let target = app("Mail")
        let launcher = FakeWorkspaceLauncher()
        launcher.missing = [target.id]
        let run = WorkspaceStartRun(targets: [target], launcher: launcher)
        var repaired = target
        repaired.url = URL(fileURLWithPath: "/nonexistent-px5/Moved/Mail.app")
        await run.retry(repaired) // Ignored before the run completes.
        #expect(launcher.opened.isEmpty)
        await run.start()
        #expect(run.results.first?.outcome == .missing)
        launcher.missing = []
        await run.retry(repaired)
        #expect(run.results.first?.outcome == .opened)
        #expect(run.results.first?.item.url == repaired.url)
        await run.retry(repaired)
        #expect(launcher.opened == [target.id])
    }

    // MARK: Portable package

    private func packageProfile() -> DockProfile {
        var stripe = DockItem.widget("Stripe")
        stripe.widgetConfiguration?.stripeAccountID = "acct_px5_private"
        stripe.widgetConfiguration?.stripeSnapshot = StripeSnapshot(
            accountID: "acct_px5_private", accountName: "PX5 Runtime Reading", fetchedAt: .now, period: .thirtyDays,
            periodStart: .now, periodEnd: .now, currencies: [], unsupportedSubscriptionItems: 0)
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "PX5 private note"
        var profile = workspaceProfile()
        profile.items += [stripe, note, .widget("AI Limits")]
        return profile
    }

    @Test func packageRoundTripPreviewsContentsAndKeepsLayout() throws {
        let profile = packageProfile()
        let data = try PortableDockPackage.makePackage(from: profile, includePersonalData: false)
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true })
        #expect(preview.profile.name == "Work")
        #expect(preview.profile.items.map(\.title) == profile.items.map(\.title))
        #expect(preview.profile.items.map(\.type) == profile.items.map(\.type))
        #expect(preview.summary == DockContentSummary(profile: profile))
        #expect(preview.summary.rows.map(\.title) == ["Apps", "Folders", "Links", "Widgets", "Spacers"])
        #expect(preview.includesPersonalData == false)
        #expect(preview.unresolved.isEmpty)
        #expect(preview.reconnections.map(\.title) == ["Stripe", "AI Limits"])
        #expect(preview.profile.workspaceTargets.map(\.title) == profile.workspaceTargets.map(\.title))
        // Still a valid backup, so Restore… accepts a Dock package.
        #expect(try BackupManager.readArchive(data).importedProfiles.count == 1)
    }

    @Test func packagesNeverCarryCredentialsOrRuntimeReadings() throws {
        let profile = packageProfile()
        let layout = String(decoding: try PortableDockPackage.makePackage(from: profile, includePersonalData: false), as: UTF8.self)
        let personal = String(decoding: try PortableDockPackage.makePackage(from: profile, includePersonalData: true), as: UTF8.self)
        for json in [layout, personal] {
            let lowered = json.lowercased()
            for secret in ["token", "secret", "password", "apikey", "api_key", "keychain"] {
                #expect(!lowered.contains(secret), "\(secret)")
            }
            #expect(!json.contains("PX5 Runtime Reading"))
            #expect(!json.contains("stripeSnapshot"))
        }
        // Personal data travels only when explicitly included; account assignments never travel.
        #expect(!layout.contains("acct_px5_private"))
        #expect(!personal.contains("acct_px5_private"))
        #expect(!layout.contains("PX5 private note"))
        #expect(personal.contains("PX5 private note"))
    }

    @Test func newerPackagesAreRefusedHonestly() {
        let newer = Data(#"{"formatVersion": 2, "exportedAt": "2030-01-01T00:00:00Z", "profiles": [], "future": true}"#.utf8)
        #expect(throws: PortableDockError.newerVersion(2)) {
            try PortableDockPackage.preview(newer, existingNames: [], targetExists: { _ in true })
        }
        #expect(PortableDockError.newerVersion(2).errorDescription?.contains("newer version of MyDock") == true)
    }

    @Test func malformedAndWrongShapeFilesAreRefusedWithoutChanges() throws {
        for text in ["not json", "[]", #"{"formatVersion": 1, "profiles": "x"}"#, #"{"formatVersion": 1, "profiles": []}"#] {
            #expect(throws: PortableDockError.malformed, "\(text)") {
                try PortableDockPackage.preview(Data(text.utf8), existingNames: [], targetExists: { _ in true })
            }
        }
        let empty = try BackupManager.makeArchive(from: [])
        #expect(throws: PortableDockError.noDock) {
            try PortableDockPackage.preview(empty, existingNames: [], targetExists: { _ in true })
        }
        let two = try BackupManager.makeArchive(from: [DockProfile(name: "A", kind: .custom), DockProfile(name: "B", kind: .custom)])
        #expect(throws: PortableDockError.multipleDocks(2)) {
            try PortableDockPackage.preview(two, existingNames: [], targetExists: { _ in true })
        }
    }

    @Test func previewListsTargetsMissingOnThisMacWithTheirFallback() throws {
        let data = try PortableDockPackage.makePackage(from: workspaceProfile(), includePersonalData: false)
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { $0.type != .application })
        #expect(preview.unresolved.map(\.title) == ["Mail", "Notes"])
        #expect(preview.unresolved.allSatisfy { $0.reason == "App not installed" && $0.fallback.contains("Locate") })
    }

    @Test func importAddsANewDockWithAFreshIdentityAndNeverOverwrites() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalID = try store.createProfile(packageProfile())
        let original = try #require(store.state.profiles.first { $0.id == originalID })
        let activeBefore = store.state.settings.activeCustomProfileID
        let countBefore = store.state.profiles.count

        let data = try PortableDockPackage.makePackage(from: original, includePersonalData: false)
        let preview = try PortableDockPackage.preview(data, existingNames: store.state.profiles.map(\.name), targetExists: { _ in true })
        #expect(preview.profile.name == "Work 2")
        let importedID = try PortableDockPackage.importAsNew(preview, into: store)

        #expect(store.state.profiles.count == countBefore + 1)
        #expect(importedID != originalID && importedID != preview.profile.id)
        #expect(store.state.profiles.first(where: { $0.id == originalID }) == original)
        #expect(store.state.settings.activeCustomProfileID == activeBefore)
        let imported = try #require(store.state.profiles.first { $0.id == importedID })
        #expect(Set(imported.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))
        #expect(imported.workspaceTargets.map(\.title) == original.workspaceTargets.map(\.title))
        // Importing the same preview again adds another copy rather than replacing one.
        let againID = try PortableDockPackage.importAsNew(preview, into: store)
        #expect(againID != importedID)
        #expect(store.state.profiles.count == countBefore + 2)
        #expect(Set(store.state.profiles.map(\.name)).count == store.state.profiles.count)
    }

    @Test func backupsWithoutAPackageManifestStillImportAsADock() throws {
        let data = try BackupManager.makeArchive(from: [DockProfile(name: "Plain", kind: .custom, items: [link("a.com")])])
        #expect(!String(decoding: data, as: UTF8.self).contains("dockPackage"))
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true })
        #expect(preview.includesPersonalData == false)
        #expect(preview.profile.name == "Plain")
    }
}

@MainActor
private final class FakeWorkspaceLauncher: WorkspaceLaunching {
    var missing: Set<UUID> = []
    var running: Set<UUID> = []
    var activationSucceeds = true
    var failures: [UUID: String] = [:]
    var onOpen: ((DockItem) -> Void)?
    private(set) var opened: [UUID] = []
    private(set) var activated: [UUID] = []
    func isMissing(_ item: DockItem) -> Bool { missing.contains(item.id) }
    func isRunning(_ item: DockItem) -> Bool { running.contains(item.id) }
    func activate(_ item: DockItem) -> Bool { activated.append(item.id); return activationSucceeds }
    func open(_ item: DockItem) async -> String? {
        opened.append(item.id)
        onOpen?(item)
        return failures[item.id]
    }
}
