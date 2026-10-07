import Foundation
import Testing
@testable import MyDock

@Suite struct RedesignAppearanceModelTests {
    // Captured with the pre-RD-02 encoder at be690ce, before model edits.
    private static let oldAppSettings = #"""
    {"automaticallyHideCustomDock":false,"automaticallySaveNativeDockChanges":false,"clickFocusedAppToMinimize":false,"customDockCornerRadius":24,"customDockDesktopMode":false,"customDockGlassOpacity":0,"customDockItemSpacing":8,"customDockMaterial":"frosted","customDockPosition":"bottom","customDockSize":1,"customDockTheme":"system","customDockTintStrength":0.08,"customDockWidgetStyle":"cards","dockAnimationStyle":"slide","dockAnimationsEnabled":true,"hideCustomDockWhenSystemDockAppears":false,"lastSettingsPage":"dock","magnificationEnabled":false,"onboardingComplete":false,"setupMode":"both","showActiveProfileNameInMenuBar":false,"showAppBadges":false,"showMinimizedWindows":false,"showRevealHandle":true,"showRunningApps":true,"showTrash":false,"showWidgetLabels":true,"showWindowPreviews":false,"smoothNativeDockSwitches":false}
    """#

    private static let oldProfileAppearance = #"""
    {"cornerRadius":24,"glassOpacity":0,"material":"frosted","showWidgetLabels":true,"size":1,"spacing":8,"theme":"system","tintStrength":0.08,"widgetStyle":"cards"}
    """#

    private static let oldWidgetConfiguration = #"""
    {"aiActivityChartStyle":"sparkline","aiActivityProvider":"codex","aiActivityRange":"today","aiActivitySecondaryMetric":"sessions","aiLimitsCompactProvider":"codex","aiLimitsLayout":"numbers","aiLimitsProviderOrder":["codex","claude","grok","cursor","geminiCLI","copilot","antigravity"],"aiLimitsRepresentation":"remaining","aiLimitsVisibleProviders":["codex","claude","grok"],"alarms":[],"appFolderApplications":[],"appFolderColor":"blue","appFolderLetter":"","appFolderName":"App Folder","calendarLayout":"dateAndNextEvent","calendarShowsAllDayEvents":false,"cardWidth":"standard","checklistEntries":[],"countdownDurationSeconds":300,"countdownElapsedBeforeStart":0,"countdownMode":"duration","focusDurationSeconds":1500,"focusElapsedBeforeStart":0,"hydrationDefaultAmountML":250,"hydrationEntries":[],"hydrationReminderIntervalMinutes":60,"hydrationRemindersEnabled":false,"hydrationSaveHistory":true,"hydrationTrackAmounts":true,"iconAppearance":"soft","iconStyle":"live","noteBackground":"yellow","noteText":"","nowPlayingEnabledSources":["appleMusic"],"nowPlayingHidesWhenClosed":false,"nowPlayingLayout":"full","nowPlayingShowsSeekControls":true,"nowPlayingShowsTrackControls":true,"nowPlayingSkipSeconds":15,"nowPlayingSource":"appleMusic","paddleAccountID":"","paddleColor":"blue","paddleDisplayName":"Paddle","paddleMetric":"netRevenue","paddlePeriod":"thirtyDays","paddleShowsChart":true,"quickLinks":[],"remindersLayout":"list","savedColors":[],"selectedCalendarIDs":[],"selectedReminderCalendarID":"","selectedShortcutName":"","shelfFiles":[],"shopifyColor":"green","shopifyDisplayName":"Shopify","shopifyMetric":"orderValue","shopifyPeriod":"thirtyDays","shopifyShowsChart":true,"shopifyStoreID":"","stockCurrency":"USD","stockName":"","stockRange":"month","stockRefreshIntervalMinutes":360,"stockShowsVolume":false,"stockSymbol":"","stopwatchElapsedBeforeStart":0,"stripeAccountID":"","stripeColor":"purple","stripeCurrency":"USD","stripeDisplayName":"Stripe","stripeMetric":"revenue","stripePeriod":"thirtyDays","systemSecondaryMetric":"memory","textSnippets":[],"timeProgressPeriod":"day","watchlistSelectedSymbol":"","watchlistStocks":[],"weatherBackground":"themed","weatherForecastHours":3,"weatherLayout":"current","weatherUnit":"celsius","worldClockAdditionalTimeZoneIDs":[],"worldClockTimeZoneID":"Europe\/Warsaw"}
    """#

    @Test func oldJSONKeepsTodaysValuesAndEveryExistingKey() throws {
        let settings = try decode(AppSettings.self, Self.oldAppSettings)
        #expect(settings == AppSettings())
        #expect(settings.customDockEdgeStyle == .hairline)
        #expect(settings.customDockWidgetSurface == .tile)
        #expect(settings.customDockFloatingInset == 0)
        #expect(settings.customDockTintMode == .custom)
        try expectOldKeysPreserved(Self.oldAppSettings, value: settings)

        let appearance = try decode(ProfileAppearance.self, Self.oldProfileAppearance)
        #expect(appearance.edgeStyle == nil)
        #expect(appearance.widgetSurface == nil)
        #expect(appearance.floatingInset == nil)
        #expect(appearance.tintMode == nil)
        #expect(appearance.applying(to: AppSettings()) == settings)
        try appearance.validate()
        try expectOldKeysPreserved(Self.oldProfileAppearance, value: appearance)

        let widget = try decode(WidgetConfiguration.self, Self.oldWidgetConfiguration)
        #expect(widget == WidgetConfiguration())
        #expect(widget.widgetAccent == nil)
        #expect(widget.showsLabel == nil)
        #expect(widget.glassTint == nil)
        try expectOldKeysPreserved(Self.oldWidgetConfiguration, value: widget)
    }

    @Test func settingsAndAppearanceRoundTripEveryNewChoice() throws {
        for edge in DockEdgeStyle.allCases {
            for surface in DockWidgetSurface.allCases {
                for mode: DockTintMode in [.custom, .auto] {
                    var settings = AppSettings()
                    settings.customDockEdgeStyle = edge
                    settings.customDockWidgetSurface = surface
                    settings.customDockFloatingInset = 17.5
                    settings.customDockTintMode = mode
                    settings.customDockTintStrength = 0
                    #expect(try roundTrip(settings) == settings)
                    let appearance = ProfileAppearance(settings: settings)
                    #expect(appearance.edgeStyle == edge)
                    #expect(appearance.widgetSurface == surface)
                    #expect(appearance.floatingInset == 17.5)
                    #expect(appearance.tintMode == mode)
                    #expect(try roundTrip(appearance) == appearance)
                    #expect(appearance.applying(to: AppSettings()) == settings)
                    try appearance.validate()
                }
            }
        }
        #expect(DockAppearanceBounds.floatingInset == 0...24)
        #expect(DockAppearanceBounds.autoTintStrength == 0.06)
    }

    @Test func oldAppearanceUsesDefaultsEvenWhenGlobalsHaveOverrides() throws {
        var globals = AppSettings()
        globals.customDockEdgeStyle = .none
        globals.customDockWidgetSurface = .glass
        globals.customDockFloatingInset = 24
        globals.customDockTintMode = .auto
        let old = try decode(ProfileAppearance.self, Self.oldProfileAppearance)
        #expect(old.applying(to: globals) == AppSettings())
    }

    @Test func widgetChoicesRoundTripWithStableAccentStrings() throws {
        let accents: [(WidgetAccent, String)] = [(.auto, "auto"), (.mono, "mono")]
            + DockProfileColor.allCases.map { (.profile($0), "profile." + $0.rawValue) }
        for (accent, raw) in accents {
            #expect(String(decoding: try JSONEncoder().encode(accent), as: UTF8.self) == "\"\(raw)\"")
            #expect(try roundTrip(accent) == accent)
            for tint: WidgetGlassTint in [.none, .accent] {
                for label in [false, true] {
                    var config = WidgetConfiguration()
                    config.widgetAccent = accent
                    config.showsLabel = label
                    config.glassTint = tint
                    #expect(try roundTrip(config) == config)
                }
            }
        }
        #expect(try roundTrip(WidgetConfiguration()) == WidgetConfiguration())
    }

    @Test func settingsClampInsetAndProfilesRejectInvalidInset() throws {
        for (input, expected) in [(-1.0, 0.0), (25.0, 24.0), (0.0, 0.0), (12.5, 12.5), (24.0, 24.0)] {
            let settings = try decode(AppSettings.self, "{\"customDockFloatingInset\":\(input)}")
            #expect(settings.customDockFloatingInset == expected)
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for raw in ["Infinity", "-Infinity", "NaN"] {
            let data = Data("{\"customDockFloatingInset\":\"\(raw)\"}".utf8)
            #expect(try decoder.decode(AppSettings.self, from: data).customDockFloatingInset == 0)
        }
        for inset in [-1.0, 25.0, Double.infinity, -Double.infinity, Double.nan] {
            var appearance = ProfileAppearance(settings: AppSettings())
            appearance.floatingInset = inset
            #expect(throws: ProfileValidationError.self) { try appearance.validate() }
            let profile = DockProfile(name: "Invalid", kind: .custom, appearance: appearance)
            #expect(throws: ProfileValidationError.self) { try ProfileSemanticValidator.validate([profile]) }
        }
        for inset: Double? in [nil, 0, 12.5, 24] {
            var appearance = ProfileAppearance(settings: AppSettings())
            appearance.floatingInset = inset
            try appearance.validate()
        }
    }

    @Test func unknownNewEnumsFallBackWithoutChangingExistingEnumDecoding() throws {
        let settings = try decode(AppSettings.self, """
        {"customDockEdgeStyle":"future","customDockWidgetSurface":"future","customDockTintMode":"future"}
        """)
        #expect(settings.customDockEdgeStyle == .hairline)
        #expect(settings.customDockWidgetSurface == .tile)
        #expect(settings.customDockTintMode == .custom)
        let appearanceJSON = try replacing(Self.oldProfileAppearance, with: [
            "edgeStyle": "future", "widgetSurface": "future", "tintMode": "future"
        ])
        let appearance = try decode(ProfileAppearance.self, appearanceJSON)
        #expect(appearance.applying(to: AppSettings()) == AppSettings())
        try appearance.validate()
        let widget = try decode(WidgetConfiguration.self, """
        {"widgetAccent":"profile.future","glassTint":"future","showsLabel":false}
        """)
        #expect(widget.widgetAccent == .auto)
        #expect(widget.glassTint == nil)
        #expect(widget.showsLabel == false)
        #expect(try decode(WidgetConfiguration.self, "{\"widgetAccent\":\"future\"}").widgetAccent == .auto)
        // S01-002: every stored choice this build does not know falls back to its default, so a file saved by a
        // newer MyDock never makes the saved data unreadable.
        #expect(try decode(AppSettings.self, "{\"customDockMaterial\":\"future\"}").customDockMaterial == .frosted)
        #expect(try decode(WidgetConfiguration.self, "{\"iconStyle\":\"future\"}").iconStyle == .live)
        let existingUnknown = try replacing(Self.oldProfileAppearance, with: ["material": "future"])
        #expect(try decode(ProfileAppearance.self, existingUnknown).material == AppSettings().customDockMaterial)
    }

    @Test func backupAndSanitizerPreserveAppearanceAndWidgetOverrides() throws {
        let profile = redesignedProfile()
        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first)
        #expect(restored.appearance == profile.appearance)
        #expect(restored.items[0].widgetConfiguration == profile.items[0].widgetConfiguration)
        let sanitized = ProfileSanitizer.sanitize(profile)
        #expect(sanitized.appearance == profile.appearance)
        #expect(sanitized.items[0].widgetConfiguration == profile.items[0].widgetConfiguration)
    }

    @Test @MainActor func personalPresetsPreserveAppearanceAndWidgetOverrides() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = redesignedProfile()
        let library = ProfileLibrary(fileURL: folder.appendingPathComponent("presets.json"))
        library.record(profile, reason: "Redesign")
        #expect(library.errorMessage == nil)
        let entry = try #require(library.entries.first)
        let data = try library.exportPreset(entry.id)
        let imported = ProfileLibrary(fileURL: folder.appendingPathComponent("imported.json"))
        try imported.importPreset(data)
        let restored = try #require(imported.entries.first?.profile)
        #expect(restored.appearance == profile.appearance)
        #expect(restored.items[0].widgetConfiguration == profile.items[0].widgetConfiguration)
        let reopened = ProfileLibrary(fileURL: folder.appendingPathComponent("imported.json"))
        #expect(reopened.errorMessage == nil)
        #expect(reopened.entries.first?.profile == restored)
    }

    @Test @MainActor func newWidgetFieldsMergeIndependentlyAndConflictingEditsStayConflicts() throws {
        let base = DockProfile(name: "Merge", kind: .custom, items: [.widget("Clock")])
        var draft = DockProfileDraft(profile: base)
        draft.update {
            $0.items[0].widgetConfiguration?.widgetAccent = .mono
            $0.items[0].widgetConfiguration?.showsLabel = false
        }
        var latest = base
        latest.items[0].widgetConfiguration?.glassTint = .accent
        let merged = try #require(draft.merged(with: latest).items[0].widgetConfiguration)
        #expect(merged.widgetAccent == .mono)
        #expect(merged.showsLabel == false)
        #expect(merged.glassTint == .accent)

        for field in ["widgetAccent", "showsLabel", "glassTint"] {
            var conflictingDraft = DockProfileDraft(profile: base)
            var conflictingLatest = base
            conflictingDraft.update {
                switch field {
                case "widgetAccent": $0.items[0].widgetConfiguration?.widgetAccent = .mono
                case "showsLabel": $0.items[0].widgetConfiguration?.showsLabel = false
                default: $0.items[0].widgetConfiguration?.glassTint = .accent
                }
            }
            switch field {
            case "widgetAccent": conflictingLatest.items[0].widgetConfiguration?.widgetAccent = .profile(.blue)
            case "showsLabel": conflictingLatest.items[0].widgetConfiguration?.showsLabel = true
            default: conflictingLatest.items[0].widgetConfiguration?.glassTint = WidgetGlassTint.none
            }
            #expect(throws: ProfileDraftMergeError.self) { try conflictingDraft.merged(with: conflictingLatest) }
        }
        var removal = DockProfileDraft(profile: redesignedProfile())
        removal.update { $0.items[0].widgetConfiguration?.widgetAccent = nil }
        var concurrent = removal.original
        concurrent.items[0].widgetConfiguration?.showsLabel = true
        let removed = try #require(removal.merged(with: concurrent).items[0].widgetConfiguration)
        #expect(removed.widgetAccent == nil)
        #expect(removed.showsLabel == true)
        #expect(removed.glassTint == .accent)
    }

    private func redesignedProfile() -> DockProfile {
        var settings = AppSettings()
        settings.customDockEdgeStyle = .contrastOnly
        settings.customDockWidgetSurface = .glass
        settings.customDockFloatingInset = 16
        settings.customDockTintMode = .auto
        var profile = DockProfile(name: "Redesign", kind: .custom, items: [.widget("Clock")])
        profile.appearance = ProfileAppearance(settings: settings)
        profile.items[0].widgetConfiguration?.widgetAccent = .profile(.teal)
        profile.items[0].widgetConfiguration?.showsLabel = false
        profile.items[0].widgetConfiguration?.glassTint = .accent
        return profile
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func replacing(_ json: String, with updates: [String: Any]) throws -> String {
        var object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object.merge(updates) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func expectOldKeysPreserved<T: Encodable>(_ json: String, value: T) throws {
        let old = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: NSObject])
        let new = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: NSObject])
        for (key, original) in old { #expect(new[key] == original, "Lost or changed old key: \(key)") }
    }
}

@Suite struct RedesignNewWidgetDefaultTests {
    @Test func newWidgetsStartMonoWhileSavedAndBareConfigurationsKeepTheirAppearance() throws {
        #expect(DockItem.widget("Clock").widgetConfiguration?.iconAppearance == .mono)
        #expect(WidgetConfiguration().iconAppearance == .soft)
        var saved = DockItem.widget("Clock")
        saved.widgetConfiguration?.iconAppearance = .accent
        let decoded = try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(saved))
        #expect(decoded.widgetConfiguration?.iconAppearance == .accent)
    }
}
