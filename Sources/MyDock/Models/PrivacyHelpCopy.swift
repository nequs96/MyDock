import Foundation

/// Concise in-app help for privacy and known limitations. Mirrors the Recovery, Backup, Trash and
/// Focus wording already shipped elsewhere.
enum PrivacyHelpCopy {
    static let privacyTitle = "Privacy and storage"
    static let privacyPoints: [String] = [
        "Docks, notes, widget settings and cached readings are stored only on this Mac, in MyDock's Application Support folder.",
        "API keys, tokens and client secrets live in this Mac's Keychain, never in profiles, history or diagnostics.",
        "Recovery history keeps layouts for 14 days. It omits credentials, connected accounts, cached readings and private text unless you include it for the current session.",
        "Backups never include credentials, permissions or cached readings. \"Include personal widget data\" adds notes, lists and saved items, so keep that file private.",
        "Diagnostics export versions, counts, settings and event codes only."
    ]

    static let limitationsTitle = "Good to know"
    static let limitationPoints: [String] = [
        "AI Activity reads local session logs. It shows usage on this Mac, not a bill or a plan quota.",
        "Empty Trash empties Finder's Trash on all volumes, including external drives MyDock does not count.",
        "Focus filters need the release version of MyDock; other copies show them as unavailable in Dock Setup.",
        "Business figures are the last stored reading. Each source line shows what it measures and when it last refreshed."
    ]
}
