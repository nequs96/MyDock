import SwiftUI

/// What's New: the copy table and the decision for when to show it.
enum WhatsNew {
    struct Entry: Identifiable, Equatable {
        var symbol: String
        var title: String
        var subtitle: String
        var id: String { title }
    }

    /// Edit this table to change the sheet. Keep it to 4-6 rows with one-line subtitles.
    static let entries: [Entry] = [
        Entry(symbol: "sparkles", title: "Redesigned Dock and widgets", subtitle: "A cleaner look, and a gallery to preview every widget."),
        Entry(symbol: "rectangle.on.rectangle", title: "Window previews", subtitle: "Optional previews when you hover a running app."),
        Entry(symbol: "arrow.down.doc", title: "Drop files on apps", subtitle: "Open files with the app they land on."),
        Entry(symbol: "speaker.wave.2", title: "Audio output widget", subtitle: "Choose the output device and set the volume."),
        Entry(symbol: "square.stack.3d.up", title: "Workspaces and portable Docks", subtitle: "Open a Dock's items together, or share a Dock."),
        Entry(symbol: "command", title: "Faster to find and switch", subtitle: "Search saved items with \u{2318}K. Docks can switch automatically."),
    ]

    /// The release the table above describes. Raise it to the shipping version whenever the
    /// table changes; a patch release that leaves the table alone does not show it again.
    static let contentVersion = "0.1.0"

    /// Never on the first launch (setup is still pending), once when the table is newer than the
    /// version last seen, and once for existing users who have never seen the sheet. The seen
    /// stamp stays the marketing version, so versions compare numerically ("0.10" after "0.9").
    static func shouldShow(lastSeenVersion: String?, contentVersion: String = WhatsNew.contentVersion,
                           onboardingComplete: Bool) -> Bool {
        guard onboardingComplete else { return false }
        guard let lastSeenVersion else { return true }
        return lastSeenVersion.compare(contentVersion, options: .numeric) == .orderedAscending
    }

    static func shouldShow(settings: AppSettings, contentVersion: String = WhatsNew.contentVersion) -> Bool {
        shouldShow(lastSeenVersion: settings.lastSeenWhatsNewVersion, contentVersion: contentVersion,
                   onboardingComplete: settings.onboardingComplete)
    }
}

struct WhatsNewView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New in \(Product.name)").font(DockDesign.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(Product.marketingVersion)").font(DockDesign.caption).foregroundStyle(.secondary)
            }
            GroupedSection {
                ForEach(WhatsNew.entries) { entry in
                    GroupedRow(entry.title, subtitle: entry.subtitle, symbol: entry.symbol, color: DockDesign.accent)
                }
            }
            HStack {
                Spacer()
                PillButton("Continue", action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DockDesign.page)
    }
}

/// Hand-maintained list of the app's shortcuts for Help > Keyboard Shortcuts. Keep it in sync
/// with the `.keyboardShortcut` call sites (DockManagerView, AddLibrary, the gallery chrome and
/// detail, and the app menu in MyDockApp).
enum KeyboardShortcutCatalog {
    struct Entry: Identifiable, Equatable {
        var title: String
        var keys: String
        var id: String { keys }
    }
    struct ShortcutGroup: Identifiable, Equatable {
        var title: String
        var entries: [Entry]
        var id: String { title }
    }

    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "General", entries: [
            Entry(title: "Search, in the Docks window", keys: "\u{2318}K"),
            Entry(title: "New Dock", keys: "\u{2318}N"),
            Entry(title: "Settings", keys: "\u{2318},"),
            Entry(title: "Manage Docks", keys: "\u{21E7}\u{2318}D"),
        ]),
        ShortcutGroup(title: "Editing a Dock", entries: [
            Entry(title: "Duplicate the selected item or Dock", keys: "\u{2318}D"),
            Entry(title: "Configure the selected item", keys: "\u{21A9}"),
            Entry(title: "Extend the selection", keys: "\u{21E7}\u{2190} \u{21E7}\u{2192}"),
            Entry(title: "Move the selected item", keys: "\u{2318}\u{2190} \u{2318}\u{2192}"),
            Entry(title: "Remove the selected item", keys: "\u{232B}"),
        ]),
        ShortcutGroup(title: "Popouts and sheets", entries: [
            Entry(title: "Close a popout", keys: "\u{2318}W"),
            Entry(title: "Close a popout, search or sheet", keys: "\u{238B}"),
        ]),
        ShortcutGroup(title: "Add Item gallery", entries: [
            Entry(title: "Switch between Widgets, Apps and More", keys: "\u{2318}1 \u{2318}2 \u{2318}3"),
            Entry(title: "Show sizes of the focused widget", keys: "\u{21A9} Space"),
            Entry(title: "Previous or next size", keys: "\u{2190} \u{2192}"),
            Entry(title: "Add the focused or highlighted item", keys: "\u{2318}\u{21A9}"),
        ]),
    ]

    static var allKeys: [String] { groups.flatMap { $0.entries.map(\.keys) } }
}

struct KeyboardShortcutsView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(DockDesign.pageTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done", action: onDone).buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(KeyboardShortcutCatalog.groups) { group in
                        GroupedSection(group.title, footer: group.title == "General" ? "Dock switching shortcuts are set in Settings." : nil) {
                            ForEach(group.entries) { entry in
                                GroupedRow(entry.title) {
                                    Text(entry.keys)
                                        .font(.system(size: 13, design: .monospaced)).monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(entry.keys)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        .background(DockDesign.page)
    }
}
