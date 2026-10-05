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

    /// Never on the first launch (setup is still pending), once after the version changes,
    /// and once for existing users who have never seen the sheet.
    static func shouldShow(lastSeenVersion: String?, currentVersion: String, onboardingComplete: Bool) -> Bool {
        guard onboardingComplete else { return false }
        return lastSeenVersion != currentVersion
    }

    static func shouldShow(settings: AppSettings, currentVersion: String = Product.marketingVersion) -> Bool {
        shouldShow(lastSeenVersion: settings.lastSeenWhatsNewVersion, currentVersion: currentVersion,
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

/// The app's real keyboard shortcuts, read from the code that defines them.
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
            Entry(title: "Search MyDock", keys: "\u{2318}K"),
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
            Entry(title: "Add in the widget gallery", keys: "\u{2318}\u{21A9}"),
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
