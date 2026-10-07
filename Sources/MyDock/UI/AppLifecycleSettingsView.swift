import AppKit
import SwiftUI

struct AppLifecycleSettingsView: View {
    @ObservedObject private var login = LaunchAtLoginController.shared
    @StateObject private var updates = UpdateCheckService()
    @State private var updateSourceExpanded = false
    @AppStorage(MyDockInterfaceAppearance.preferenceKey, store: AppRuntimeEnvironment.defaults) private var interfaceAppearance = "system"
    @AppStorage("app.mydock.release-repository", store: AppRuntimeEnvironment.defaults) private var repositoryURL = ""
    private var loginFooter: String {
        switch login.state {
        case .unavailable: "Launch at login is not available in this session."
        case .notRegistered: "Not registered to launch at login."
        case .enabled: "Allowed to launch at login."
        case .requiresApproval: "Approve MyDock in Login Items."
        case .notFound: "macOS could not find this login service."
        case .unknown: "Check the login status in Login Items."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupedSection("Application", footer: loginFooter) {
                SettingsControlRow(title: "MyDock appearance") {
                    Picker("MyDock appearance", selection: $interfaceAppearance) {
                        ForEach(MyDockInterfaceAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).frame(width: 220)
                }
                GroupedRow("Launch at login", isOn: Binding(get: { login.state.registrationRequested }, set: { login.setEnabled($0) })).disabled(!login.isAvailable)
                if login.requiresApproval { GroupedRow("Approve in Login Items…", role: .button) { login.openApprovalSettings() } }
                if login.state == .notFound || login.state == .unknown { GroupedRow("Open Login Items…", role: .button) { login.openApprovalSettings() } }
                if let error = login.errorMessage { GroupedRow(error).foregroundStyle(.orange) }
            }.id("Application").help(login.state.message)
            GroupedSection("Updates", footer: "Updates are checked only when requested.") {
                GroupedRow("Installed version", value: Product.marketingVersion)
                // Stays enabled without a source: the check explains what is missing and the source field opens.
                GroupedRow("Check for Updates", role: .button) {
                    if ReleaseRepository(url: repositoryURL) == nil { updateSourceExpanded = true }
                    Task { await updates.check(repositoryURL: repositoryURL) }
                }
                .disabled(updates.checking)
                if updates.checking { GroupedRow("Checking for updates") { ProgressView().controlSize(.small) } }
                if let url = updates.releaseURL { GroupedRow("New version available") { Link("Review Release", destination: url) } }
                SettingsExpansionRow(title: "Update source", isExpanded: $updateSourceExpanded) {
                    TextField("Publisher’s GitHub repository URL", text: $repositoryURL)
                        .textFieldStyle(DockTextFieldStyle()).disabled(updates.checking)
                        .help("Choose the publisher's release repository. New versions open on the release page.")
                }
                if let message = updates.message { GroupedRow(message).textSelection(.enabled) }
            }.id("Updates")
        }.onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .onChange(of: repositoryURL) { _ in updates.clearResult() }
    }
}
