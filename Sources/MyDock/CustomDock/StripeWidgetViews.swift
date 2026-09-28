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
        VStack(spacing: 2) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color(for: configuration.stripeColor))
            if let value = metricText {
                Text(value)
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(configuration.stripeMetric.title)
                    .font(.system(size: 7, weight: .medium)).lineLimit(1)
            } else {
                Text("Connect").font(.system(size: 8, weight: .medium)).lineLimit(1)
            }
            if let snapshot = configuration.stripeSnapshot,
               Date.now.timeIntervalSince(snapshot.fetchedAt) > 300 {
                Circle().fill(.orange).frame(width: 4, height: 4)
            }
        }
        .frame(width: 54, height: 54)
        .help(tooltip)
    }

    private var metricText: String? {
        guard let values else { return nil }
        return StripeMetricFormatter.text(for: configuration.stripeMetric, values: values)
    }

    private var tooltip: String {
        guard let snapshot = configuration.stripeSnapshot else { return "Stripe · Add a restricted API key in Integrations" }
        return "\(configuration.stripeDisplayName) · \(configuration.stripeMetric.title) · \(snapshot.accountName) · Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct StripePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var isRefreshing = false
    @State private var isConnecting = false
    @State private var connectionNameDraft = ""
    @State private var restrictedKeyDraft = ""
    @State private var newConnectionColor = DockProfileColor.purple.rawValue
    @State private var connections: [StripeConnectedAccount] = []
    @State private var showingDisconnectConfirmation = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: StripeSnapshot? { configuration.stripeSnapshot }
    private var currencyMetrics: StripeCurrencyMetrics? { snapshot?.metrics(for: configuration.stripeCurrency) }

    var body: some View {
        ScrollView(.vertical) {
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
        }
        .frame(width: 360, height: 480)
        .task(id: "\(configuration.stripeAccountID)|\(configuration.stripePeriod.rawValue)") {
            guard !configuration.stripeAccountID.isEmpty else { return }
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: 300) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        .onAppear(perform: reloadConnections)
        .confirmationDialog("Disconnect \(configuration.stripeDisplayName)?",
                            isPresented: $showingDisconnectConfirmation,
                            titleVisibility: .visible) {
            Button("Disconnect and Remove Key", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the restricted key from this Mac's Keychain. It does not revoke the key in Stripe.")
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
                TextField("Account name", text: $connectionNameDraft)
                    .textFieldStyle(.roundedBorder)
                Picker("Account color", selection: $newConnectionColor) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            SecureField("Restricted key (rk_live_… or rk_test_…)", text: $restrictedKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().controlSize(.small) }
                    else { Text("Connect") }
                }
                .disabled(isConnecting || connectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || restrictedKeyDraft.isEmpty)
                if !configuration.stripeAccountID.isEmpty {
                    Button("Disconnect", role: .destructive) { showingDisconnectConfirmation = true }
                }
                Spacer()
                if let url = URL(string: "https://docs.stripe.com/keys#limit-access") {
                    Link("Key permissions", destination: url)
                }
            }
            Text("Grant only Core → Balance: Read and Billing → Subscriptions: Read. MyDock never requests write access.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
        let selectedAccountID = requestedAccountID ?? configuration.stripeAccountID
        guard !isRefreshing, !selectedAccountID.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let account = StripeConnectionDirectory.accounts().first(where: { $0.id == selectedAccountID }) else {
                throw StripeDataError.missingKey
            }
            guard let key = try StripeAPIKeyStore.read(accountID: account.id) else { throw StripeDataError.missingKey }
            let result = try await StripeAPIProvider().snapshot(apiKey: key,
                                                                accountID: account.id,
                                                                accountName: configuration.stripeDisplayName,
                                                                period: configuration.stripePeriod)
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                guard value.stripeAccountID == selectedAccountID,
                      value.stripePeriod == result.period else { return }
                value.stripeCurrency = result.currencyCodes.contains(value.stripeCurrency)
                    ? value.stripeCurrency
                    : (result.currencyCodes.first ?? "USD")
                value.stripeSnapshot = result
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        errorMessage = nil
        let key = restrictedKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = connectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await StripeAPIProvider().validate(apiKey: key)
            let account = StripeConnectedAccount(name: name, color: newConnectionColor)
            try StripeConnectionDirectory.save(account, key: key)
            restrictedKeyDraft = ""
            connectionNameDraft = ""
            reloadConnections()
            update {
                $0.stripeAccountID = account.id
                $0.stripeDisplayName = account.name
                $0.stripeColor = account.color
                $0.stripeCurrency = "USD"
                $0.stripeSnapshot = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let id = configuration.stripeAccountID
        guard !id.isEmpty else { return }
        do {
            try StripeConnectionDirectory.remove(accountID: id)
            reloadConnections()
            update { $0.stripeAccountID = ""; $0.stripeSnapshot = nil }
            errorMessage = nil
        } catch {
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
    switch DockProfileColor(rawValue: name) ?? .purple {
    case .blue: .blue
    case .purple: .purple
    case .teal: .teal
    case .green: .green
    case .orange: .orange
    case .pink: .pink
    case .red: .red
    }
}
