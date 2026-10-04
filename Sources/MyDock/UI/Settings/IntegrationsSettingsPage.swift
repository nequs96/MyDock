import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var integrationsPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        GroupedSection("AI accounts on this Mac", footer: "Existing Codex and Claude Code accounts appear automatically; sign in with the provider to add one.") {
            AIAccountConnectionView(provider: .codex, allowsAccountActions: store.allowsSystemChanges)
            AIAccountConnectionView(provider: .claude, allowsAccountActions: store.allowsSystemChanges, showsLimitsSetup: true)
        }.id("AI accounts on this Mac")
        ConnectionsCenterView(store: store)
        PrivacyHelpSection()
        GroupedSection("Market data") {
            integrationSummary("Alpha Vantage", symbol: "chart.line.uptrend.xyaxis", connected: marketAPIKeySaved)
            DisclosureGroup("Manage API key", isExpanded: $marketConnectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Stock and Watchlist use Alpha Vantage end-of-day data with free-tier limits; your personal key stays in Keychain, outside backups.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            SecureField(marketAPIKeySaved ? "Key saved in Keychain" : "Alpha Vantage API key", text: $marketAPIKeyDraft)
                .textFieldStyle(DockTextFieldStyle())
            HStack {
                Button("Save Key") { saveMarketAPIKey() }
                    .disabled(marketAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Key", role: .destructive) { removeMarketAPIKey() }
                    .disabled(!marketAPIKeySaved)
                Spacer()
                if let url = URL(string: "https://www.alphavantage.co/support/#api-key") {
                    Link("Get a key", destination: url)
                }
            }
            }.padding(.top, 12)
            }
            if let marketAPIKeyMessage {
                Text(marketAPIKeyMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.id("Market data")
        GroupedSection("GitHub Copilot usage") {
            integrationSummary("GitHub Copilot", symbol: "sparkles", connected: copilotCredentialsSaved)
            DisclosureGroup("Manage credentials", isExpanded: $copilotConnectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Personal Copilot AI-credit usage uses read-only billing; organization and enterprise usage are excluded. Give the token Plan: read access; it stays in Keychain, outside profiles and backups.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
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
                Button("Remove Credentials", role: .destructive) { removeCopilotCredentials() }
                    .disabled(!copilotCredentialsSaved)
                Spacer()
                if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                    Link("Create token", destination: url)
                }
            }
            }.padding(.top, 12)
            }
            if let copilotCredentialsMessage {
                Text(copilotCredentialsMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.id("GitHub Copilot usage")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
        updateMarketAPIKeyState()
        updateCopilotCredentialState()
    }
    }

    private func integrationSummary(_ title: String, symbol: String, connected: Bool) -> some View {
        GroupedRow(title, symbol: symbol, color: .green, value: connected ? "Connected" : "Not connected")
    }

    private func updateMarketAPIKeyState() {
        do {
            marketAPIKeySaved = try MarketAPIKeyStore.read() != nil
            if marketAPIKeySaved { marketAPIKeyMessage = "The key is saved locally in Keychain." }
        } catch {
            marketAPIKeySaved = false
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private func updateCopilotCredentialState() {
        do {
            let credentials = try GitHubCopilotCredentialStore.read()
            copilotCredentialsSaved = credentials != nil
            copilotUsernameDraft = credentials?.username ?? ""
            if copilotCredentialsSaved {
                copilotCredentialsMessage = "Personal GitHub credentials are saved in this Mac's Keychain."
            }
        } catch {
            copilotCredentialsSaved = false
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
