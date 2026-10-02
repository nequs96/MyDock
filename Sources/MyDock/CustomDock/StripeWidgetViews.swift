import SwiftUI

struct StripeWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StripeCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StripePopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct StripeCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var values: StripeCurrencyMetrics? { configuration.stripeSnapshot?.metrics(for: configuration.stripeCurrency) }

    var body: some View {
        BusinessDockFace(kind: "Stripe", title: configuration.stripeDisplayName, metric: configuration.stripeMetric.title, value: values.map { StripeMetricFormatter.text(for: configuration.stripeMetric, values: $0) }, context: configuration.stripePeriod.title)
    }
}

private struct StripePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var isConnecting = false
    @State private var connections: [StripeConnectedAccount] = []
    @State private var showingDisconnectConfirmation = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: StripeSnapshot? { configuration.stripeSnapshot }
    private var currencyMetrics: StripeCurrencyMetrics? { snapshot?.metrics(for: configuration.stripeCurrency) }
    private var setupDraft: StripeConnectionDraft { setupDrafts.stripeDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill").foregroundStyle(color(for: configuration.stripeColor))
                TextField("Account name", text: displayNameBinding)
                    .textFieldStyle(.plain).font(.headline)
                Spacer(minLength: 4)
                Button("Refresh") { Task { await refresh() } }
                    .disabled(isRefreshing)
                if isRefreshing { ProgressView().controlSize(.small) }
            }

            if let snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.accountName).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text("Restricted, read-only connection").font(.caption2).foregroundStyle(.tertiary)
                }
                .help("Account name is local to MyDock. The API key determines the Stripe account.")
            } else {
                Label("Connect a restricted Stripe key", systemImage: "key.horizontal")
                    .font(.callout.weight(.medium))
                Text("Add an rk_ key in Settings → Integrations. Use read-only access for Account, Balance, Balance Transactions, and Subscriptions.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if let currencyMetrics {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StripeMetricFormatter.text(for: configuration.stripeMetric, values: currencyMetrics))
                        .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                    HStack(spacing: 6) {
                        Text(configuration.stripeMetric.title)
                        Text("·")
                        Text(configuration.stripeCurrency)
                        if [.revenue, .netAfterFees].contains(configuration.stripeMetric) {
                            Text("·")
                            Text((snapshot?.period ?? configuration.stripePeriod).title)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            } else if snapshot != nil {
                Text("No \(configuration.stripeCurrency) data is available for this account yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            controls

            connectionControls

            if let snapshot {
                HStack(spacing: 5) {
                    Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                    Text(isStale ? "Showing last successful values" : "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    Text("·")
                    Text(TimeZone.autoupdatingCurrent.identifier)
                }
                .font(.caption2).foregroundStyle(isStale ? Color.orange : Color.gray)
                if snapshot.unsupportedSubscriptionItems > 0 {
                    Text("Skipped \(snapshot.unsupportedSubscriptionItems) complex subscription item(s) from MRR/ARR.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let errorMessage {
                Label(snapshot == nil ? errorMessage : "Refresh failed. Showing saved data. \(errorMessage)",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot, snapshot.period != configuration.stripePeriod,
               [.revenue, .netAfterFees].contains(configuration.stripeMetric) {
                Text("Last successful period: \(snapshot.period.title) · selected: \(configuration.stripePeriod.title)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Revenue is payment activity posted to the Stripe balance, less refunds and payment reversals, before fees. It includes collected tax and excludes payouts, transfers, and disputes. Net uses Stripe's transaction net after fees. Currencies are never converted.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            Text("MRR/ARR estimate active and past-due fixed recurring prices; trials and metered, tiered, discounted, or tax-adjusted items are excluded.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 350, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .task(id: "\(configuration.stripeAccountID)|\(configuration.stripePeriod.rawValue)|\(configuration.stripeDisplayName)") {
            guard !configuration.stripeAccountID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadConnections)
        .confirmationDialog("Disconnect \(configuration.stripeDisplayName)?",
                            isPresented: $showingDisconnectConfirmation,
                            titleVisibility: .visible) {
            Button("Disconnect and Remove Key", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the restricted key from this Mac's Keychain and disconnects every MyDock widget using it. It does not revoke the key in Stripe.")
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                Text("Metric").foregroundStyle(.secondary)
                Picker("Metric", selection: metricBinding) {
                    ForEach(StripeMetric.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Account").foregroundStyle(.secondary)
                Picker("Account", selection: accountBinding) {
                    Text("Not connected").tag("")
                    ForEach(connections) { account in Text(account.name).tag(account.id) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Currency").foregroundStyle(.secondary)
                Picker("Currency", selection: currencyBinding) {
                    ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(currencyOptions.isEmpty)
            }
            GridRow {
                Text("Period").foregroundStyle(.secondary)
                Picker("Period", selection: periodBinding) {
                    ForEach(StripePeriod.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .disabled([.revenue, .netAfterFees].contains(configuration.stripeMetric) == false)
            }
            GridRow {
                Text("Color").foregroundStyle(.secondary)
                Picker("Color", selection: colorBinding) {
                    ForEach(DockProfileColor.allCases) { color in
                        Text(color.title).tag(color.rawValue)
                    }
                }
                .labelsHidden()
            }
        }
        .font(.caption)
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            Text("Connect a Stripe account").font(.caption.weight(.semibold))
            HStack(spacing: 7) {
                TextField("Account name", text: connectionNameBinding)
                    .textFieldStyle(DockTextFieldStyle())
                    .disabled(isConnecting)
                Picker("Account color", selection: connectionColorBinding) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 100)
                .disabled(isConnecting)
            }
            SecureField("Restricted key (rk_live_… or rk_test_…)", text: restrictedKeyBinding)
                .textFieldStyle(DockTextFieldStyle())
                .disabled(isConnecting)
            HStack {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().controlSize(.small) }
                    else { Text("Connect") }
                }
                .disabled(isConnecting || setupDraft.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setupDraft.restrictedKey.isEmpty)
                if !configuration.stripeAccountID.isEmpty {
                    Button("Disconnect", role: .destructive) { showingDisconnectConfirmation = true }
                }
                Button("Clear Draft") { setupDrafts.clearDrafts(for: item.id) }
                    .disabled(isConnecting || setupDraft.isPristine)
                Spacer()
                if let url = URL(string: "https://docs.stripe.com/keys#limit-access") {
                    Link("Key permissions", destination: url)
                }
            }
            Text("Grant read-only Account, Balance, Balance Transactions, and Subscriptions access. MyDock never requests write access.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("An unfinished form stays in memory for this widget until connected or cleared; its key is never written to profile data or backups.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionNameBinding: Binding<String> {
        Binding(get: { setupDraft.accountName }, set: { value in
            setupDrafts.updateStripeDraft(for: item.id) { $0.accountName = String(value.prefix(80)) }
        })
    }

    private var restrictedKeyBinding: Binding<String> {
        Binding(get: { setupDraft.restrictedKey }, set: { value in
            setupDrafts.updateStripeDraft(for: item.id) { $0.restrictedKey = value }
        })
    }

    private var connectionColorBinding: Binding<String> {
        Binding(get: { setupDraft.color }, set: { value in
            setupDrafts.updateStripeDraft(for: item.id) { $0.color = value }
        })
    }

    private var currencyOptions: [String] {
        let options = snapshot?.currencyCodes ?? []
        return options.isEmpty ? [configuration.stripeCurrency] : options
    }

    private var isStale: Bool {
        guard let snapshot else { return false }
        return Date.now.timeIntervalSince(snapshot.fetchedAt) > 300 || snapshot.period != configuration.stripePeriod
    }

    private var displayNameBinding: Binding<String> {
        Binding(get: { configuration.stripeDisplayName }, set: { value in
            update { $0.stripeDisplayName = String(value.prefix(80)) }
        })
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.stripeAccountID }, set: { accountID in
            guard let account = connections.first(where: { $0.id == accountID }) else {
                update { $0.stripeAccountID = ""; $0.stripeSnapshot = nil }
                return
            }
            update {
                $0.stripeAccountID = account.id
                $0.stripeDisplayName = account.name
                $0.stripeColor = account.color
                $0.stripeCurrency = "USD"
                $0.stripeSnapshot = nil
            }
            errorMessage = nil
        })
    }

    private var metricBinding: Binding<StripeMetric> {
        Binding(get: { configuration.stripeMetric }, set: { value in update { $0.stripeMetric = value } })
    }

    private var currencyBinding: Binding<String> {
        Binding(get: { configuration.stripeCurrency }, set: { value in update { $0.stripeCurrency = value } })
    }

    private var periodBinding: Binding<StripePeriod> {
        Binding(get: { configuration.stripePeriod }, set: { value in update { $0.stripePeriod = value } })
    }

    private var colorBinding: Binding<String> {
        Binding(get: { configuration.stripeColor }, set: { value in
            update { $0.stripeColor = value }
            if let account = connections.first(where: { $0.id == configuration.stripeAccountID }) {
                StripeConnectionDirectory.update(StripeConnectedAccount(id: account.id, name: account.name, color: value))
                reloadConnections()
            }
        })
    }

    private func refresh(accountID requestedAccountID: String? = nil) async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID)
        guard refreshRequestID == requestID, !Task.isCancelled else { return }
        if let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: configuration) {
            errorMessage = store.widgetData.errors[query]
        }
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        errorMessage = nil
        let draft = setupDraft
        let key = draft.restrictedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = draft.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await StripeAPIProvider().validate(apiKey: key)
            guard !Task.isCancelled,
                  let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
                    .first(where: { $0.id == item.id && $0.widgetKind == "Stripe" }),
                  (currentItem.widgetConfiguration ?? WidgetConfiguration()).stripeAccountID.isEmpty else { return }
            let account = StripeConnectedAccount(name: name, color: draft.color)
            try StripeConnectionDirectory.save(account, key: key)
            setupDrafts.clearDrafts(for: item.id)
            reloadConnections()
            update {
                $0.stripeAccountID = account.id
                $0.stripeDisplayName = account.name
                $0.stripeColor = account.color
                $0.stripeCurrency = "USD"
                $0.stripeSnapshot = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiagnosticsService.shared.record(.stripeConnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let id = configuration.stripeAccountID
        guard !id.isEmpty else { return }
        refreshRequestID = UUID()
        isRefreshing = false
        do {
            try StripeConnectionDirectory.remove(accountID: id)
            reloadConnections()
            store.clearConnectionReferences(.stripe(id))
            errorMessage = nil
        } catch {
            DiagnosticsService.shared.record(.stripeDisconnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func reloadConnections() {
        connections = StripeConnectionDirectory.accounts()
    }

    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }
}

private enum StripeMetricFormatter {
    static func text(for metric: StripeMetric, values: StripeCurrencyMetrics) -> String {
        switch metric {
        case .revenue: money(values.revenueMinor, currency: values.currency)
        case .netAfterFees: money(values.netAfterFeesMinor, currency: values.currency)
        case .mrr: money(values.mrrMinor, currency: values.currency)
        case .arr: money(values.mrrMinor * 12, currency: values.currency)
        case .payingSubscribers: values.payingSubscribers.formatted()
        case .arpu: money(values.arpuMinor, currency: values.currency)
        case .availableBalance: money(values.availableBalanceMinor, currency: values.currency)
        case .pendingBalance: money(values.pendingBalanceMinor, currency: values.currency)
        }
    }

    private static func money(_ minorUnits: Decimal, currency: String) -> String {
        FinancialCurrencyFormatter.text(from: minorUnits, currency: currency)
    }
}

private func color(for name: String) -> Color {
    (DockProfileColor(rawValue: name) ?? .purple).displayColor
}
