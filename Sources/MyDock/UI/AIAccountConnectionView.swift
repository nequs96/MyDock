import SwiftUI
import AppKit

struct AIAccountConnectionView: View {
    var provider: AIProvider
    var allowsAccountActions: Bool
    var showsLimitsSetup = false
    var settingsPresentation = false
    var settingsHeader: String? = nil
    var settingsFooter: String? = nil
    var refresh: () async -> Void = {}
    @State private var status: AIAccountStatus?
    @State private var checking = false
    @State private var limitsEnabled = false
    @State private var message: String?

    private var directory: URL { status?.configurationDirectory ?? AIAccountService.claudeDirectory() }

    var body: some View {
        Group {
        if settingsPresentation {
            settingsAccount
        } else {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: provider == .codex ? "terminal" : "sparkle")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(DockDesign.accent)
                    .frame(width: 32, height: 32).background(DockDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider == .claude ? "Claude Code" : "Codex").font(.system(size: 13, weight: .semibold))
                    Text(checking ? "Looking for an account on this Mac…" : status?.message ?? "Find an account already signed in on this Mac")
                        .font(DockDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if checking { ProgressView().controlSize(.small) }
                else if status?.state == .signedIn { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            accountActions
            if provider == .claude, showsLimitsSetup {
                Text(limitsEnabled ? "Limits sync automatically while you use Claude Code. Requires Claude Code 2.1.251 or later."
                     : "Enable Limits adds usage sync to Claude Code’s status line and keeps your current terminal display. A backup of its settings is saved.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message { Text(message).font(DockDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12).modifier(AppSurface())
        }
        }
        .task(id: provider) { await findAccount(refreshData: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await findAccount(refreshData: true) }
        }
    }

    private var accountActions: some View {
        HStack(spacing: 8) {
                Button(status?.state == .notInstalled ? "Get \(provider == .claude ? "Claude Code" : "Codex")" : "Sign In…") {
                    do { try AIAccountService.signIn(provider); message = "Finish signing in in Terminal, then return here." }
                    catch { message = "Could not open sign-in. Open \(provider.title) and sign in, then choose Find Account." }
                }
                .disabled(!allowsAccountActions || checking)
                Button("Find Account") { Task { await findAccount(refreshData: true) } }
                    .disabled(!allowsAccountActions || checking)
                    .accessibilityLabel("Find \(provider.title) account on this Mac")
                if !settingsPresentation, provider == .claude, showsLimitsSetup {
                    if limitsEnabled {
                        Button("Turn Off Limits") { disableLimits() }.disabled(!allowsAccountActions)
                            .help("Restores Claude Code’s previous status line and removes the limits snapshot.")
                    } else if status?.state == .signedIn {
                        Button("Enable Limits") { enableLimits() }.disabled(!allowsAccountActions)
                    }
                }
            }.controlSize(.small)
    }

    /// One card per provider under the page's "AI accounts" heading: the row names the provider,
    /// so the card has no title of its own, and the shared footer is shown once by the page.
    private var settingsAccount: some View {
        GroupedSection(settingsHeader, footer: settingsFooter) {
            GroupedRow(provider == .claude ? "Claude Code" : "Codex",
                       subtitle: checking ? "Looking for an account on this Mac…" : status?.message ?? "Find an account already signed in on this Mac",
                       symbol: provider == .codex ? "terminal" : "sparkle", color: .gray) {
                if checking { ProgressView().controlSize(.small) }
                else if status?.state == .signedIn { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            accountActions.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            if provider == .claude, showsLimitsSetup {
                if limitsEnabled {
                    GroupedRow("Limits sync", subtitle: "Requires Claude Code 2.1.251 or later.") {
                        Button("Turn Off") { disableLimits() }
                            .controlSize(.small)
                            .disabled(!allowsAccountActions || checking)
                            .accessibilityLabel("Turn off Claude Code limits sync")
                            .help("Restores Claude Code’s previous status line and removes the limits snapshot.")
                    }
                } else {
                    GroupedRow("Enable Limits", role: .button) { enableLimits() }
                        .disabled(!allowsAccountActions || checking || status?.state != .signedIn)
                        .help(status?.state == .signedIn
                              ? "Adds usage sync to Claude Code’s status line, keeps your terminal display and saves a settings backup."
                              : "Sign in to Claude Code first.")
                }
            }
            if let message { GroupedRow(message).textSelection(.enabled) }
        }
    }

    private func enableLimits() {
        do {
            try ClaudeLimitsSetup.enable(directory: directory)
            limitsEnabled = true
            message = "Limits sync enabled. Start or restart Claude Code and use it once to receive limits."
            Task { await refresh() }
        } catch let error as ClaudeLimitsSetupError {
            message = error.localizedDescription
        } catch { message = "Could not update Claude Code settings. Your existing settings were preserved." }
    }

    private func disableLimits() {
        do {
            try ClaudeLimitsSetup.disable(directory: directory)
            limitsEnabled = false
            message = "Limits sync is off. Claude Code’s previous status line is restored."
            Task { await refresh() }
        } catch let error as ClaudeLimitsSetupError {
            message = error.localizedDescription
        } catch { message = "Could not update Claude Code settings. Your existing settings were preserved." }
    }

    private func findAccount(refreshData: Bool) async {
        guard allowsAccountActions, !checking else { return }
        checking = true
        let detected = await AIAccountService.detectInBackground(provider)
        guard !Task.isCancelled else { checking = false; return }
        status = detected
        if provider == .claude { limitsEnabled = ClaudeLimitsSetup.isEnabled(directory: directory) }
        checking = false
        if detected.state == .signedIn { message = nil }
        if refreshData { await refresh() }
    }
}
