import AppKit
import SwiftUI

struct AppLifecycleSettingsView: View {
    @ObservedObject private var login = LaunchAtLoginController.shared
    @StateObject private var updates = UpdateCheckService()
    @State private var updateSourceExpanded = false
    @AppStorage(MyDockInterfaceAppearance.preferenceKey, store: AppRuntimeEnvironment.defaults) private var interfaceAppearance = "system"
    @AppStorage("app.mydock.release-repository", store: AppRuntimeEnvironment.defaults) private var repositoryURL = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DockSettingSection(title: "Application") {
                SettingsControlRow(title: "MyDock appearance") {
                    Picker("MyDock appearance", selection: $interfaceAppearance) {
                        ForEach(MyDockInterfaceAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).frame(width: 220)
                }
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) })).disabled(!login.isAvailable)
                if login.requiresApproval { Button("Approve in Login Items…") { login.openApprovalSettings() } }
                if let error = login.errorMessage { Text(error).font(DockDesign.caption).foregroundStyle(.orange) }
            }
            DockSettingSection(title: "Updates") {
                SettingsControlRow(title: "Installed version") { Text(Product.marketingVersion).foregroundStyle(.secondary) }
                HStack {
                    if updates.checking { ProgressView().controlSize(.small) }
                    if let url = updates.releaseURL { Link("Review Release", destination: url) }
                    Spacer()
                    Button("Check for Updates") { Task { await updates.check(repositoryURL: repositoryURL) } }
                        .disabled(updates.checking || repositoryURL.isEmpty)
                }
                DisclosureGroup("Update source", isExpanded: $updateSourceExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Publisher’s GitHub repository URL", text: $repositoryURL)
                            .textFieldStyle(DockTextFieldStyle()).disabled(updates.checking)
                        Text("Choose the publisher's release repository. Checks run when requested, and new versions open on the release page.")
                            .font(DockDesign.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
                if let message = updates.message { Text(message).font(DockDesign.caption).textSelection(.enabled) }
            }
        }.onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .onChange(of: repositoryURL) { _ in updates.clearResult() }
    }
}
