import AppKit
import SwiftUI
import Testing
@testable import MyDock

/// FX-03: safe Remove Widget, Start button contrast, the sheet's hero suppression, compact face text
/// (disk, period tokens, sticky note) and one module alignment rule.
@MainActor
struct FX03Tests {
    /// A state writer that fails while `failing` is set (the store keeps its edit in memory).
    final class SwitchableWriter: @unchecked Sendable {
        private let lock = NSLock()
        private var shouldFail = false
        var failing: Bool {
            get { lock.lock(); defer { lock.unlock() }; return shouldFail }
            set { lock.lock(); shouldFail = newValue; lock.unlock() }
        }
        struct Injected: Error {}
        lazy var writer = RevisionedStateWriter { [unowned self] state, url in
            if self.failing { throw Injected() }
            try RevisionedStateWriter.persist(state, to: url)
        }
    }

    private func makeStore(writer: RevisionedStateWriter? = nil) throws -> (ProfileStore, UUID, [DockItem], URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FX03Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false, stateWriter: writer)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "FX-03")
        let items = [DockItem.widget("Clock"), DockItem.widget("Weather"), DockItem.widget("Battery")]
        for item in items { store.add(item, to: profileID) }
        store.flush()
        return (store, profileID, items, root)
    }

    private func savedItemIDs(_ root: URL, _ profileID: UUID) throws -> [UUID]? {
        let state = try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: root.appendingPathComponent("state.json")))
        return state.profiles.first { $0.id == profileID }?.items.map(\.id)
    }

    // MARK: Remove Widget

    @Test func failedRemovalSaveStaysPendingThenRetrySavesAndRegistersUndo() throws {
        let switchable = SwitchableWriter()
        let (store, profileID, items, root) = try makeStore(writer: switchable.writer)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!store.hasUnpersistedChanges)
        let undo = UndoManager()

        switchable.failing = true
        #expect(throws: EditSessionSaveError.self) {
            try WidgetSheetRemoval.remove(itemID: items[1].id, profileID: profileID, store: store, undoManager: undo)
        }
        // Not saved, no undo yet, and the removal is remembered for a retry.
        #expect(!undo.canUndo)
        #expect(WidgetSheetRemoval.hasPendingRemoval(itemID: items[1].id))
        #expect(try savedItemIDs(root, profileID) == items.map(\.id))

        // Retrying while the disk still fails keeps it pending.
        #expect(throws: EditSessionSaveError.self) {
            try WidgetSheetRemoval.remove(itemID: items[1].id, profileID: profileID, store: store, undoManager: undo)
        }
        #expect(WidgetSheetRemoval.hasPendingRemoval(itemID: items[1].id))
        #expect(!undo.canUndo)

        // Once the disk recovers, the retry saves the removal (it used to return false here).
        switchable.failing = false
        let removed = try WidgetSheetRemoval.remove(itemID: items[1].id, profileID: profileID, store: store, undoManager: undo)
        #expect(removed)
        #expect(!WidgetSheetRemoval.hasPendingRemoval(itemID: items[1].id))
        #expect(try savedItemIDs(root, profileID) == [items[0].id, items[2].id])
        #expect(store.editSessions.drafts[profileID]?.isDirty == false)
        #expect(undo.canUndo)
        undo.undo()
        #expect(store.editSessions.drafts[profileID]?.profile.items.map(\.id) == items.map(\.id))
    }

    @Test func successfulRemovalSavesOnceAndLeavesNothingPending() throws {
        let (store, profileID, items, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let undo = UndoManager()
        #expect(try WidgetSheetRemoval.remove(itemID: items[0].id, profileID: profileID, store: store, undoManager: undo))
        #expect(!WidgetSheetRemoval.hasPendingRemoval(itemID: items[0].id))
        #expect(try savedItemIDs(root, profileID) == [items[1].id, items[2].id])
        #expect(undo.canUndo)
        #expect(try WidgetSheetRemoval.remove(itemID: items[0].id, profileID: profileID, store: store) == false)
    }

    @Test func removalRejectedBeforeTheStoreChangesRollsTheDraftBack() throws {
        let (store, profileID, items, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        // An empty profile name fails validation before the store is touched.
        let edits = store.editSessions
        let profile = try #require(store.state.profiles.first { $0.id == profileID })
        edits.load(profile)
        var draft = try #require(edits.drafts[profileID])
        draft.update { $0.name = "   " }
        edits.set(draft, for: profileID)
        let undo = UndoManager()
        #expect(throws: ProfileDraftMergeError.self) {
            try WidgetSheetRemoval.remove(itemID: items[2].id, profileID: profileID, store: store, undoManager: undo)
        }
        #expect(!undo.canUndo)
        #expect(!WidgetSheetRemoval.hasPendingRemoval(itemID: items[2].id))
        // The draft is exactly as it was, so the item is still there and a later removal can run.
        #expect(edits.drafts[profileID]?.profile.items.map(\.id) == items.map(\.id))
        #expect(edits.drafts[profileID]?.profile.name == "   ")
        #expect(store.state.profiles.first { $0.id == profileID }?.items.map(\.id) == items.map(\.id))
    }

    // MARK: Start contrast

    @Test func tintedRoundButtonsMeetTextContrastInEveryAppearance() {
        for role in [WidgetRoundButtonRole.start, .pause] {
            for dark in [false, true] {
                let standard = WidgetRoundButtonPalette.colors(role, dark: dark, increasedContrast: false)!
                let increased = WidgetRoundButtonPalette.colors(role, dark: dark, increasedContrast: true)!
                let normalRatio = WidgetRoundButtonPalette.contrast(standard.foreground, standard.fill)
                let increasedRatio = WidgetRoundButtonPalette.contrast(increased.foreground, increased.fill)
                #expect(normalRatio >= 4.5, "\(role) dark=\(dark): \(normalRatio)")
                #expect(increasedRatio >= 7, "\(role) dark=\(dark) IC: \(increasedRatio)")
                #expect(increasedRatio > normalRatio)
            }
            // Light mode: white text on a solid tint.
            #expect(WidgetRoundButtonPalette.colors(role, dark: false, increasedContrast: false)?.foreground == WidgetRoundButtonPalette.white)
        }
        #expect(WidgetRoundButtonPalette.colors(.neutral, dark: false, increasedContrast: false) == nil)
        // The previous light Start (system green text on an 18 % green wash over white) was about 2:1.
        let green = WidgetRoundButtonPalette.RGB(red: 0.204, green: 0.780, blue: 0.349)
        let wash = WidgetRoundButtonPalette.RGB(red: 1 - 0.18 * (1 - 0.204), green: 1 - 0.18 * (1 - 0.780), blue: 1 - 0.18 * (1 - 0.349))
        #expect(WidgetRoundButtonPalette.contrast(green, wash) < 2.5)
    }

    // MARK: Hero suppression

    @Test func sheetSuppressesHeroesExceptToolOutput() {
        #expect(WidgetSheetHeroPolicy.showsHero(kind: "Clock", inSheet: false))
        for kind in ["Clock", "Weather", "Trash", "Alarm", "Disk Space", "Countdown", "World Clock"] {
            #expect(!WidgetSheetHeroPolicy.showsHero(kind: kind, inSheet: true), "\(kind)")
        }
        #expect(WidgetSheetHeroPolicy.showsHero(kind: "Unit Converter", inSheet: true))
        // Clock's content is only its hero, so the sheet shows no Content for it.
        #expect(!WidgetSheetHeroPolicy.showsContent(kind: "Clock", inSheet: true))
        #expect(WidgetSheetHeroPolicy.showsContent(kind: "Clock", inSheet: false))
        #expect(WidgetSheetHeroPolicy.showsContent(kind: "Weather", inSheet: true))
        #expect(EnvironmentValues().widgetPopoutShowsHero)
    }

    @Test func heroRendersNothingWhenTheSheetFlagIsOff() {
        func height(_ shows: Bool) -> CGFloat {
            let view = WidgetPopoutHero(value: "12:00", caption: "Monday").environment(\.widgetPopoutShowsHero, shows)
                .frame(width: 300).fixedSize(horizontal: false, vertical: true)
            return NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 1_000)).height
        }
        #expect(height(true) > 40)
        #expect(height(false) < 1)
    }

    // MARK: Compact face text

    @Test func diskFacesUseThreeSignificantDigits() {
        let fractional = DiskSpaceFaceText.compact(120_620_000_000)
        #expect(fractional.contains("121"))
        #expect(!fractional.contains("62"))
        #expect(DiskSpaceFaceText.compact(128_000_000_000).contains("128"))
        #expect(DiskSpaceFaceText.compact(-5).first?.isNumber == true)
        #expect(DiskSpaceFaceText.compact(0).first?.isNumber == true)
        // Never longer than the old adaptive text.
        #expect(fractional.count <= ByteCountFormatter.string(fromByteCount: 120_620_000_000, countStyle: .file).count)
    }

    @Test func periodTitlesBecomeCompactTokens() {
        for period in StripePeriod.allCases { #expect(WidgetPeriodToken.compact(period.title).count <= 5, "\(period.title)") }
        for period in PaddlePeriod.allCases { #expect(WidgetPeriodToken.compact(period.title).count <= 5, "\(period.title)") }
        for period in ShopifyPeriod.allCases { #expect(WidgetPeriodToken.compact(period.title).count <= 5, "\(period.title)") }
        #expect(WidgetPeriodToken.compact("Today") == "Today")
        #expect(WidgetPeriodToken.compact("7 days") == "7d")
        #expect(WidgetPeriodToken.compact("30 days") == "30d")
        #expect(WidgetPeriodToken.compact("Last 30 days") == "30d")
        #expect(WidgetPeriodToken.compact("Last 7 days") == "7d")
        #expect(WidgetPeriodToken.compact("90 days") == "90d")
        #expect(WidgetPeriodToken.compact("Month to date") == "Month")
        // Other trailing readings pass through untouched.
        #expect(WidgetPeriodToken.compact("+1.2%") == "+1.2%")
        #expect(WidgetPeriodToken.compact("Oct 5") == "Oct 5")
    }

    @Test func stickyNoteFlowsAsOneTextAndKeepsWholeWords() {
        #expect(StickyNoteFaceText.flowing("Make something great.\nTake a little break.") == "Make something great. Take a little break.")
        #expect(StickyNoteFaceText.flowing("  \n ") == StickyNoteFaceText.placeholder)
        #expect(StickyNoteFaceText.firstWord("\nCall Mia") == "Call")
        #expect(StickyNoteFaceText.firstWord("") == nil)
    }

    @Test func modulesCentreWithoutALabel() {
        #expect(ModuleAlignmentPolicy.alignment(narrow: false, showsLabel: true) == .leading)
        #expect(ModuleAlignmentPolicy.alignment(narrow: false, showsLabel: false) == .center)
        #expect(ModuleAlignmentPolicy.alignment(narrow: true, showsLabel: true) == .center)
        #expect(!ModuleAlignmentPolicy.fillsRow(narrow: false, showsLabel: false, keepsLeading: true))
        #expect(ModuleAlignmentPolicy.fillsRow(narrow: false, showsLabel: true, keepsLeading: true))
    }

    @Test func appFolderColoursComeFromTheWidgetPalette() {
        for color in DockProfileColor.allCases {
            #expect(WidgetPalette.profile(color) == color.displayColor)
            #expect(WidgetPalette.resolved(kind: "App Folder", accent: .profile(color)) == WidgetPalette.profile(color))
        }
    }

    // MARK: Customize panel

    /// The popout with its Customize panel (size pager + Appearance) open stays as rigid as FX-01 requires.
    @Test func customizePanelKeepsThePopoutVerticallyRigid() throws {
        let (store, profileID, items, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let shown = try #require(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == items[0].id })
        let view = AnyView(WidgetPopout(store: store, item: shown, profileID: profileID).customizeExpandedForQA()
            .environment(\.dockSnapshotRendering, true))
        let measure = NSHostingController(rootView: view)
        let squeezed = measure.sizeThatFits(in: CGSize(width: 460, height: 1)).height
        let roomy = measure.sizeThatFits(in: CGSize(width: 460, height: 20_000)).height
        #expect(abs(squeezed - roomy) < 0.5, "customize popout \(squeezed) vs \(roomy)")
        #expect(roomy > 300)
    }
}

@Suite struct WidgetPopoutHeroStyleTests {
    @Test func readingsStayLargeAndStatesBecomeCalmStatus() {
        for reading in ["72%", "21°", "$2.4K", "12", "7:30", "121 GB"] {
            #expect(WidgetPopoutHeroStyle.automatic(for: reading) == .reading)
        }
        for state in ["Connect Stripe", "Unavailable", "Warming up", "Choose a ticker", "Empty", "Off"] {
            #expect(WidgetPopoutHeroStyle.automatic(for: state) == .status)
        }
    }
}
