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
            DockSettingSection(title: "Global profile shortcuts") {
                Text("Assign a keyboard shortcut to switch to any saved macOS Dock or Custom Dock profile. Shortcuts work while MyDock is in the background, require at least two modifiers, and are stored only on this Mac.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.state.profiles.isEmpty {
                    Text("Create a Dock profile in Manage Docks to assign a shortcut.")
                        .font(.callout).foregroundStyle(.secondary)
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
            }
            DockSettingSection(title: "Shortcut privacy") {
                Text("Shortcuts are excluded from profile backups because key combinations are local to this Mac. MyDock shows a warning beside any shortcut the system could not register.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    }
}
