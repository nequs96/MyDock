import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !store.nativeProfiles.isEmpty {
            Section("macOS Dock") {
                ForEach(store.nativeProfiles) { profile in
                    Button {
                        store.activate(profile.id)
                    } label: {
                        if store.state.settings.activeNativeProfileID == profile.id { Label(profile.name, systemImage: "checkmark") }
                        else { Text(profile.name) }
                    }
                }
            }
        }
        if !store.customProfiles.isEmpty {
            Section("Custom Dock") {
                ForEach(store.customProfiles) { profile in
                    Button {
                        store.activate(profile.id)
                    } label: {
                        if store.state.settings.activeCustomProfileID == profile.id { Label(profile.name, systemImage: "checkmark") }
                        else { Text(profile.name) }
                    }
                }
            }
        }
        Divider()
        Button("Manage Docks…") { openWindow(id: "manager") }
        Button("Settings…") { openWindow(id: "settings") }
        Button("About \(Product.name)") { openWindow(id: "about") }
        Divider()
        Button("Quit \(Product.name)") { NSApplication.shared.terminate(nil) }
    }
}
