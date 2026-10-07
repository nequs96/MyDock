import Foundation

enum ProfileValidationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let field): "Invalid profile data: \(field). The original data has been kept." }
    }
}

enum ProfileSemanticValidator {
    static let maximumTimerDuration = 366 * 86_400
    static let maximumElapsed: TimeInterval = 100 * 366 * 86_400
    static let maximumProfiles = 500
    static let maximumItems = 20_000

    static func validate(_ profiles: [DockProfile]) throws {
        guard profiles.count <= maximumProfiles, Set(profiles.map(\.id)).count == profiles.count else {
            throw ProfileValidationError.invalid("too many profiles or duplicate profile identities")
        }
        var itemIDs = Set<UUID>()
        var count = 0
        for profile in profiles {
            try profile.appearance?.validate()
            guard profile.name.count <= 500 else { throw ProfileValidationError.invalid("profile name is too long") }
            for item in profile.items {
                count += 1
                guard count <= maximumItems, itemIDs.insert(item.id).inserted else {
                    throw ProfileValidationError.invalid("too many items or duplicate item identities")
                }
                if let configuration = item.widgetConfiguration { try validate(configuration) }
            }
        }
    }

    static func validate(_ config: WidgetConfiguration) throws {
        guard (0...maximumTimerDuration).contains(config.focusDurationSeconds),
              (0...maximumTimerDuration).contains(config.countdownDurationSeconds),
              [config.focusElapsedBeforeStart, config.countdownElapsedBeforeStart, config.stopwatchElapsedBeforeStart]
                .allSatisfy({ $0.isFinite && (0...maximumElapsed).contains($0) }) else {
            throw ProfileValidationError.invalid("timer duration or elapsed time is outside the supported range")
        }
        guard config.shelfFiles.count <= FileShelfPolicy.capacity,
              Set(config.shelfFiles.map(\.id)).count == config.shelfFiles.count,
              config.shelfFiles.allSatisfy({ $0.url.isFileURL && $0.url.absoluteString.utf8.count <= 32_768 && ($0.bookmark?.count ?? 0) <= 65_536 }),
              config.textSnippets.count <= 50,
              Set(config.textSnippets.map(\.id)).count == config.textSnippets.count,
              config.textSnippets.allSatisfy({ $0.title.utf8.count <= 400 && $0.text.utf8.count <= 40_000 }),
              config.quickLinks.count <= 50,
              Set(config.quickLinks.map(\.id)).count == config.quickLinks.count,
              config.quickLinks.allSatisfy({ $0.title.utf8.count <= 400 && $0.url.absoluteString.utf8.count <= 8_192 && DockLinkPolicy.validatedURL($0.url.absoluteString) != nil }),
              config.savedColors.count <= 24, Set(config.savedColors).count == config.savedColors.count,
              config.savedColors.allSatisfy({ HexColor.components($0) != nil }) else {
            throw ProfileValidationError.invalid("file shelf, snippets, links or palette exceeds supported limits")
        }
        guard config.checklistEntries.count <= 100,
              Set(config.checklistEntries.map(\.id)).count == config.checklistEntries.count,
              config.checklistEntries.allSatisfy({ $0.title.utf8.count <= 2_000 }) else {
            throw ProfileValidationError.invalid("quick checklist exceeds supported limits")
        }
        guard config.noteText.utf8.count <= 1_048_576,
              config.hydrationEntries.count <= 50_000,
              (1...20_000).contains(config.hydrationDefaultAmountML),
              WidgetConfiguration.hydrationReminderIntervalRange.contains(config.hydrationReminderIntervalMinutes),
              config.hydrationEntries.allSatisfy({ $0.amountML.map { (1...20_000).contains($0) } ?? true }),
              Set(config.hydrationEntries.map(\.id)).count == config.hydrationEntries.count else {
            throw ProfileValidationError.invalid("note or hydration history exceeds supported limits")
        }
        guard config.alarms.count <= 64, Set(config.alarms.map(\.id)).count == config.alarms.count,
              config.alarms.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute)
                && $0.repeatWeekdays.allSatisfy({ (1...7).contains($0) }) }),
              config.appFolderApplications.count <= 2_000,
              Set(config.appFolderApplications.map(\.id)).count == config.appFolderApplications.count,
              config.watchlistStocks.count <= 100,
              Set(config.watchlistStocks.map(\.id)).count == config.watchlistStocks.count,
              config.worldClockAdditionalTimeZoneIDs.count <= 100,
              (1...1_440).contains(config.stockRefreshIntervalMinutes),
              config.hydrationLastRemovedEntry?.amountML.map({ (1...20_000).contains($0) }) ?? true else {
            throw ProfileValidationError.invalid("alarm, app folder, watchlist, or clock configuration")
        }
        for snapshot in [config.stockSnapshot].compactMap({ $0 }) + config.watchlistStocks.compactMap(\.snapshot) {
            guard snapshot.points.count <= 10_000,
                  snapshot.points.allSatisfy({ $0.close.isFinite && $0.close >= 0 && $0.volume >= 0 }) else {
                throw ProfileValidationError.invalid("market chart data")
            }
        }
        guard config.aiLimitsSnapshot?.isValid ?? true, config.aiActivitySnapshot?.isValid ?? true else {
            throw ProfileValidationError.invalid("cached AI usage data")
        }
        let dates = [config.focusStartedAt, config.countdownStartedAt, config.stopwatchStartedAt, config.countdownTargetDate]
            .compactMap { $0 } + config.hydrationEntries.map(\.timestamp) + [config.hydrationLastRemovedEntry?.timestamp].compactMap { $0 }
        guard dates.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite
            && abs($0.timeIntervalSinceReferenceDate) <= 315_576_000_000 }) else {
            throw ProfileValidationError.invalid("date is outside the supported range")
        }
    }
}

enum TimerValueFormatter {
    static func text(_ interval: TimeInterval) -> String {
        let finite = interval.isFinite ? interval : 0
        let seconds = Int(min(max(0, finite), ProfileSemanticValidator.maximumElapsed).rounded(.up))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
