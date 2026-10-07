import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var shortcutsPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
            GroupedSection("Global Dock shortcuts", footer: "Shortcuts stay on this Mac.") {
                if store.state.profiles.isEmpty {
                    GroupedNote("Create a Dock in Manage Docks to assign a shortcut.")
                } else {
                    ForEach(store.state.profiles) { profile in
                        SettingsShortcutRow(
                            profile: profile,
                            shortcut: shortcutBindings.shortcut(for: profile.id),
                            registrationMessage: shortcutController.statusMessages[profile.id],
                            edit: {
                                editingShortcutProfile = profile
                            }
                        )
                    }
                }
            }.id("Global Dock shortcuts").help("Shortcuts need two modifiers, work from any app, stay on this Mac and are excluded from backups; registration failures appear beside each Dock.")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    }
}
