import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

/// A Keychain credential that Settings → Integrations can remove after confirmation.
enum IntegrationCredentialKind: Identifiable {
    case marketAPIKey, copilot
    var id: Self { self }
    var removalTitle: String {
        switch self {
        case .marketAPIKey: "Remove the Alpha Vantage key?"
        case .copilot: "Remove GitHub Copilot credentials?"
        }
    }
}

extension SettingsView {
    var integrationsPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        VStack(alignment: .leading, spacing: 20) {
            AIAccountConnectionView(provider: .codex, allowsAccountActions: store.allowsSystemChanges, settingsPresentation: true,
                                    settingsHeader: "AI accounts")
            AIAccountConnectionView(provider: .claude, allowsAccountActions: store.allowsSystemChanges, showsLimitsSetup: true, settingsPresentation: true,
                                    settingsFooter: "Sign in with the provider to add an account.")
        }.id("AI accounts on this Mac")
        ConnectionsCenterView(store: store)
        PrivacyHelpSection()
        GroupedSection("Market data") {
            integrationSummary("Alpha Vantage", symbol: "chart.line.uptrend.xyaxis", connected: marketAPIKeySaved)
            SettingsExpansionRow(title: "Manage API key", isExpanded: $marketConnectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Stock and Watchlist use Alpha Vantage end-of-day data with free-tier limits; your personal key stays in Keychain, outside backups.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField(marketAPIKeySaved ? "Key saved in Keychain" : "Alpha Vantage API key", text: $marketAPIKeyDraft)
                .textFieldStyle(DockTextFieldStyle())
            HStack {
                Button("Save Key") { saveMarketAPIKey() }
                    .disabled(marketAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Key…", role: .destructive) { pendingCredentialRemoval = .marketAPIKey }
                    .disabled(!marketAPIKeySaved)
                Spacer()
                if let url = URL(string: "https://www.alphavantage.co/support/#api-key") {
                    Link("Get a key", destination: url)
                }
            }
            }
            }
            if let marketAPIKeyMessage { GroupedNote(marketAPIKeyMessage) }
        }.id("Market data")
        GroupedSection("GitHub Copilot usage") {
            integrationSummary("GitHub Copilot", symbol: "sparkles", connected: copilotCredentialsSaved)
            SettingsExpansionRow(title: "Manage credentials", isExpanded: $copilotConnectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Personal Copilot AI-credit usage uses read-only billing; organization and enterprise usage are excluded. Give the token Plan: read access; it stays in Keychain, outside profiles and backups.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("GitHub username", text: $copilotUsernameDraft)
                .textFieldStyle(DockTextFieldStyle())
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField(copilotCredentialsSaved ? "Replace saved fine-grained token" : "Fine-grained personal access token",
                        text: $copilotTokenDraft)
                .textFieldStyle(DockTextFieldStyle())
                .textContentType(.password)
                .autocorrectionDisabled()
            HStack {
                Button(copilotCredentialsSaved ? "Update Credentials" : "Save Credentials") {
                    saveCopilotCredentials()
                }
                .disabled(copilotTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          !GitHubCopilotUsernamePolicy.isValid(copilotUsernameDraft))
                Button("Remove Credentials…", role: .destructive) { pendingCredentialRemoval = .copilot }
                    .disabled(!copilotCredentialsSaved)
                Spacer()
                if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                    Link("Create token", destination: url)
                }
            }
            }
            }
            if let copilotCredentialsMessage { GroupedNote(copilotCredentialsMessage) }
        }.id("GitHub Copilot usage")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
        updateMarketAPIKeyState()
        updateCopilotCredentialState()
    }
    // Typed secrets do not outlive the form that holds them.
    .onDisappear { clearCredentialDrafts() }
    .onChange(of: marketConnectionExpanded) { expanded in if !expanded { marketAPIKeyDraft = "" } }
    .onChange(of: copilotConnectionExpanded) { expanded in
        if expanded { fillCopilotUsernameIfEmpty() } else { copilotTokenDraft = "" }
    }
    .confirmationDialog(pendingCredentialRemoval?.removalTitle ?? "", isPresented: Binding(
        get: { pendingCredentialRemoval != nil }, set: { if !$0 { pendingCredentialRemoval = nil } })) {
        Button("Remove from Keychain", role: .destructive) {
            if let kind = pendingCredentialRemoval {
                switch kind {
                case .marketAPIKey: removeMarketAPIKey()
                case .copilot: removeCopilotCredentials()
                }
            }
            pendingCredentialRemoval = nil
        }
    } message: { Text("Widgets using it stop updating.") }
    }

    private func integrationSummary(_ title: String, symbol: String, connected: Bool) -> some View {
        GroupedRow(title, symbol: symbol, color: .green, value: connected ? "Connected" : "Not connected")
    }

    private func clearCredentialDrafts() {
        marketAPIKeyDraft = ""
        copilotTokenDraft = ""
    }

    /// Existence only: the key itself is not read to show a status.
    private func updateMarketAPIKeyState() {
        do {
            marketAPIKeySaved = try MarketAPIKeyStore.exists()
            if marketAPIKeySaved { marketAPIKeyMessage = "The key is saved locally in Keychain." }
        } catch {
            marketAPIKeySaved = false
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    /// Existence only; the saved username is read when the credentials form opens.
    private func updateCopilotCredentialState() {
        do {
            copilotCredentialsSaved = try GitHubCopilotCredentialStore.exists()
            if copilotConnectionExpanded { fillCopilotUsernameIfEmpty() }
            if copilotCredentialsSaved {
                copilotCredentialsMessage = "Personal GitHub credentials are saved in this Mac's Keychain."
            }
        } catch {
            copilotCredentialsSaved = false
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    /// Prefills the saved username without overwriting an edit in progress.
    private func fillCopilotUsernameIfEmpty() {
        guard copilotCredentialsSaved, copilotUsernameDraft.isEmpty else { return }
        do {
            copilotUsernameDraft = try GitHubCopilotCredentialStore.read()?.username ?? ""
        } catch {
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private func saveCopilotCredentials() {
        do {
            try GitHubCopilotCredentialStore.write(username: copilotUsernameDraft, token: copilotTokenDraft)
            store.invalidateCopilotLimitReadings()
            copilotTokenDraft = ""
            copilotCredentialsSaved = true
            copilotCredentialsMessage = "Saved in Keychain. AI Limits can now read personal Copilot billing usage."
        } catch {
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private func removeCopilotCredentials() {
        do {
            try GitHubCopilotCredentialStore.delete()
            store.invalidateCopilotLimitReadings()
            copilotTokenDraft = ""
            copilotCredentialsSaved = false
            copilotCredentialsMessage = "Removed from Keychain."
        } catch {
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private func saveMarketAPIKey() {
        let key = marketAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try MarketAPIKeyStore.write(key)
            marketAPIKeyDraft = ""
            marketAPIKeySaved = true
            store.widgetData.connectionsDidChange()
            marketAPIKeyMessage = "Saved in Keychain. The Stock and Watchlist widgets can use it now."
        } catch {
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private func removeMarketAPIKey() {
        do {
            try MarketAPIKeyStore.delete()
            store.widgetData.connectionsDidChange()
            marketAPIKeyDraft = ""
            marketAPIKeySaved = false
            marketAPIKeyMessage = "Removed from Keychain."
        } catch {
            marketAPIKeyMessage = error.localizedDescription
        }
    }
}
