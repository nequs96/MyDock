import Foundation
import OSLog

enum DiagnosticCategory: String, Codable {
    case lifecycle
    case nativeDock
    case customDock
    case widgets
    case permissions
    case integrations
    case persistence
    case focus
    case backup
    case windowManagement
}

enum DiagnosticEventCode: String, Codable {
    case appLaunched
    case quitRequested
    case quitCancelled
    case appTerminated
    case stateRecovered
    case stateRecoveryFailed
    case stateSaveFailed
    case stateSaveRecovered
    case runtimeCacheRecovered
    case runtimeCacheSaveFailed
    case nativeApplyStarted
    case nativeApplySucceeded
    case nativeApplyFailed
    case nativeRollbackFailed
    case nativeInterruptedRecoverySucceeded
    case customDockShown
    case customDockHidden
    case permissionStatusRefreshed
    case backupExported
    case backupImported
    case backupOperationFailed
    case focusProfileApplied
    case focusProfileUnavailable
    case weatherSearchFailed
    case weatherLocationFailed
    case weatherRefreshFailed
    case stripeRefreshFailed
    case stripeConnectionFailed
    case stripeDisconnectionFailed
    case paddleRefreshFailed
    case paddleConnectionFailed
    case paddleDisconnectionFailed
    case shopifyRefreshFailed
    case shopifyConnectionFailed
    case shopifyDisconnectionFailed
    case customDockDisplayFallback
    case customDockDisplayRestored
    case customDockScreenUnavailable

    var category: DiagnosticCategory {
        switch self {
        case .appLaunched, .quitRequested, .quitCancelled, .appTerminated: .lifecycle
        case .stateRecovered, .stateRecoveryFailed, .stateSaveFailed, .stateSaveRecovered,
             .runtimeCacheRecovered, .runtimeCacheSaveFailed: .persistence
        case .nativeApplyStarted, .nativeApplySucceeded, .nativeApplyFailed,
             .nativeRollbackFailed, .nativeInterruptedRecoverySucceeded: .nativeDock
        case .customDockShown, .customDockHidden: .customDock
        case .permissionStatusRefreshed: .permissions
        case .backupExported, .backupImported, .backupOperationFailed: .backup
        case .focusProfileApplied, .focusProfileUnavailable: .focus
        case .weatherSearchFailed, .weatherLocationFailed, .weatherRefreshFailed: .widgets
        case .stripeRefreshFailed, .stripeConnectionFailed, .stripeDisconnectionFailed,
             .paddleRefreshFailed, .paddleConnectionFailed, .paddleDisconnectionFailed,
             .shopifyRefreshFailed, .shopifyConnectionFailed, .shopifyDisconnectionFailed: .integrations
        case .customDockDisplayFallback, .customDockDisplayRestored, .customDockScreenUnavailable: .windowManagement
        }
    }
}

struct DiagnosticEvent: Codable {
    let at: Date
    let category: DiagnosticCategory
    let code: DiagnosticEventCode
}

struct DiagnosticReport: Codable {
    struct Counts: Codable {
        let nativeProfiles: Int
        let customProfiles: Int
        let applications: Int
        let folders: Int
        let files: Int
        let links: Int
        let spacers: Int
        let widgets: Int
    }

    struct Status: Codable {
        let onboardingComplete: Bool
        let hasUnpersistedChanges: Bool
        let persistenceWarningPresent: Bool
        let storageWritable: Bool
    }

    struct Appearance: Codable {
        let setupMode: SetupMode
        let dockPosition: DockPosition
        let dockMaterial: CustomDockMaterial
        let dockSize: Double
        let widgetStyle: CustomDockWidgetStyle
        let autoHide: Bool
        let desktopMode: Bool
    }

    let formatVersion: Int
    let generatedAt: Date
    let appVersion: String
    /// CFBundleVersion of the running bundle, or "unbundled" when run outside an app bundle.
    let buildNumber: String
    /// True when the bundle carries App Intents metadata, which identifies the Xcode-built app.
    let hasIntentMetadata: Bool
    let stateSchemaVersion: Int
    let macOSMajorVersion: Int
    let macOSMinorVersion: Int
    let macOSPatchVersion: Int
    let counts: Counts
    let status: Status
    let appearance: Appearance
    let recentEvents: [DiagnosticEvent]

    static func currentBuildNumber(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unbundled"
    }

    static func makeData(state: PersistentState, hasUnpersistedChanges: Bool,
                         persistenceWarningPresent: Bool, storageWritable: Bool,
                         events: [DiagnosticEvent], now: Date = .now,
                         buildNumber: String = DiagnosticReport.currentBuildNumber(),
                         hasIntentMetadata: Bool = FocusFilterAvailability.hasIntentMetadata(),
                         osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) throws -> Data {
        let items = state.profiles.flatMap(\.items)
        let counts = Counts(nativeProfiles: state.profiles.filter { $0.kind == .native }.count,
                            customProfiles: state.profiles.filter { $0.kind == .custom }.count,
                            applications: items.filter { $0.type == .application }.count,
                            folders: items.filter { $0.type == .folder }.count,
                            files: items.filter { $0.type == .file }.count,
                            links: items.filter { $0.type == .link }.count,
                            spacers: items.filter { $0.type == .spacer }.count,
                            widgets: items.filter { $0.type == .widget }.count)
        let settings = state.settings
        let report = DiagnosticReport(formatVersion: 2, generatedAt: now,
                                      appVersion: Product.marketingVersion,
                                      buildNumber: buildNumber,
                                      hasIntentMetadata: hasIntentMetadata,
                                      stateSchemaVersion: state.schemaVersion,
                                      macOSMajorVersion: osVersion.majorVersion,
                                      macOSMinorVersion: osVersion.minorVersion,
                                      macOSPatchVersion: osVersion.patchVersion,
                                      counts: counts,
                                      status: Status(onboardingComplete: settings.onboardingComplete,
                                                     hasUnpersistedChanges: hasUnpersistedChanges,
                                                     persistenceWarningPresent: persistenceWarningPresent,
                                                     storageWritable: storageWritable),
                                      appearance: Appearance(setupMode: settings.setupMode,
                                                             dockPosition: settings.customDockPosition,
                                                             dockMaterial: settings.customDockMaterial,
                                                             dockSize: settings.customDockSize,
                                                             widgetStyle: settings.customDockWidgetStyle,
                                                             autoHide: settings.automaticallyHideCustomDock,
                                                             desktopMode: settings.customDockDesktopMode),
                                      recentEvents: Array(events.suffix(200)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

@MainActor
final class DiagnosticsService {
    static let shared = DiagnosticsService()
    private(set) var events: [DiagnosticEvent] = []
    private init() {}

    func record(_ code: DiagnosticEventCode) {
        let event = DiagnosticEvent(at: .now, category: code.category, code: code)
        events.append(event)
        if events.count > 200 { events.removeFirst(events.count - 200) }
        Logger(subsystem: Product.bundleIdentifier, category: code.category.rawValue)
            .notice("\(code.rawValue, privacy: .public)")
    }

    func reportData(for store: ProfileStore) throws -> Data {
        try DiagnosticReport.makeData(state: store.state,
                                      hasUnpersistedChanges: store.hasUnpersistedChanges,
                                      persistenceWarningPresent: store.persistenceWarning != nil,
                                      storageWritable: store.canRetryPersistence,
                                      events: events)
    }
}
