import SwiftUI

struct StripeWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StripeCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StripePopoutView(store: store, item: item, profileID: profileID))
    }
}

struct StripeCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var values: StripeCurrencyMetrics? { configuration.stripeSnapshot?.metrics(for: configuration.stripeCurrency) }

    var body: some View {
        FacesBBusinessDockFace(kind: "Stripe", title: configuration.stripeDisplayName, metric: configuration.stripeMetric.title,
            amount: values.map { StripeMetricFormatter.amount(for: configuration.stripeMetric, values: $0) },
            currency: configuration.stripeMetric == .payingSubscribers ? nil : configuration.stripeCurrency,
            fullValue: values.map { StripeMetricFormatter.text(for: configuration.stripeMetric, values: $0) },
            context: configuration.stripePeriod.title,
            emptyValue: configuration.stripeSnapshot != nil || !configuration.stripeAccountID.isEmpty ? "No data" : "Connect")
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
            GroupedSection {
                GroupedRow("Account name", symbol: "pencil") {
                    TextField("Account name", text: displayNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                }
                GroupedRow("Refresh", symbol: "arrow.clockwise") {
                    Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing)
                    if isRefreshing { ProgressView().controlSize(.small) }
                }
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
                        .font(DockDesign.Module.valueLarge)
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
                Text("No \(configuration.stripeCurrency) data is available. Choose a currency reported by this account in the Currency menu.")
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
            DataSourceProvenanceView(provenance: .stripe(snapshot: snapshot, localName: configuration.stripeDisplayName,
                                                         metric: configuration.stripeMetric, error: errorMessage))
            Text("Revenue is payment activity posted to the Stripe balance, less refunds and payment reversals, before fees. It includes collected tax and excludes payouts, transfers, and disputes. Net uses Stripe's transaction net after fees. Currencies are never converted.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            Text("MRR/ARR estimate active and past-due fixed recurring prices; trials and metered, tiered, discounted, or tax-adjusted items are excluded.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        GroupedSection("Display") {
            GroupedRow("Metric") {
                Picker("Metric", selection: metricBinding) {
                    ForEach(StripeMetric.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            GroupedRow("Account") {
                Picker("Account", selection: accountBinding) {
                    Text("Not connected").tag("")
                    ForEach(connections) { account in Text(account.name).tag(account.id) }
                }
                .labelsHidden()
            }
            GroupedRow("Currency") {
                Picker("Currency", selection: currencyBinding) {
                    ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(currencyOptions.isEmpty)
            }
            GroupedRow("Period") {
                Picker("Period", selection: periodBinding) {
                    ForEach(StripePeriod.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .disabled([.revenue, .netAfterFees].contains(configuration.stripeMetric) == false)
            }
            GroupedRow("Color") {
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
            GroupedSection("Connect a Stripe account") {
                GroupedRow("Account name") {
                    TextField("Account name", text: connectionNameBinding)
                        .textFieldStyle(DockTextFieldStyle())
                        .disabled(isConnecting)
                }
                GroupedRow("Account color") {
                    Picker("Account color", selection: connectionColorBinding) {
                        ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()

                    .disabled(isConnecting)
                }
                GroupedRow("Restricted key") {
                    SecureField("Restricted key (rk_live_… or rk_test_…)", text: restrictedKeyBinding)
                        .textFieldStyle(DockTextFieldStyle())
                        .disabled(isConnecting)
                }
                GroupedRow("Connect", role: .button) { Task { await connect() } }
                    .disabled(isConnecting || setupDraft.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setupDraft.restrictedKey.isEmpty)
                if isConnecting { GroupedRow("Connecting…") { ProgressView().controlSize(.small) } }
                GroupedRow("Clear Draft", role: .button) { setupDrafts.clearDrafts(for: item.id) }
                    .disabled(isConnecting || setupDraft.isPristine)
                if !configuration.stripeAccountID.isEmpty {
                    GroupedRow("Disconnect", role: .destructive) { showingDisconnectConfirmation = true }
                }
                if let url = URL(string: "https://docs.stripe.com/keys#limit-access") {
                    GroupedRow("Permissions") { Link("Key permissions", destination: url) }
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
        return options.contains(configuration.stripeCurrency) ? options : [configuration.stripeCurrency] + options
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

    static func amount(for metric: StripeMetric, values: StripeCurrencyMetrics) -> Decimal {
        let minor: Decimal
        switch metric {
        case .payingSubscribers: return Decimal(values.payingSubscribers)
        case .revenue: minor = values.revenueMinor
        case .netAfterFees: minor = values.netAfterFeesMinor
        case .mrr: minor = values.mrrMinor
        case .arr: minor = values.mrrMinor * 12
        case .arpu: minor = values.arpuMinor
        case .availableBalance: minor = values.availableBalanceMinor
        case .pendingBalance: minor = values.pendingBalanceMinor
        }
        return FinancialCurrencyFormatter.majorUnits(from: minor, currency: values.currency)
    }

    private static func money(_ minorUnits: Decimal, currency: String) -> String {
        FinancialCurrencyFormatter.text(from: minorUnits, currency: currency)
    }
}

private func color(for name: String) -> Color {
    (DockProfileColor(rawValue: name) ?? .purple).displayColor
}

/// Compact financial values retain a full currency/count description for VoiceOver and help.
enum FacesBFinancialFormatting {
    static func compact(_ amount: Decimal, currency: String?, narrow: Bool, locale: Locale = .current) -> String {
        let number = NSDecimalNumber(decimal: amount).doubleValue
        guard number.isFinite else { return "—" }
        let scales: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        let scale = scales.first { abs(number) >= $0.0 } ?? (1, "")
        let text = (number / scale.0).formatted(.number.locale(locale).precision(.fractionLength(0...(scale.0 == 1 ? 2 : 1)))) + scale.1
        guard let currency, !narrow else { return text }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return (formatter.currencySymbol ?? currency) + text
    }
    static func stateColor(_ amount: Decimal?) -> Color { amount.map { $0 < 0 ? WidgetPalette.critical : Color.primary } ?? .primary }
}

struct FacesBBusinessDockFace: View {
    var kind: String
    var title: String
    var metric: String
    var amount: Decimal?
    var currency: String?
    var fullValue: String?
    var context: String
    var emptyValue = "Connect"
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        let narrow = WidgetModuleMetrics.isNarrow(width)
        ModuleStack(kind: kind, label: fullValue == nil || title.count > 12 ? kind : title,
                    value: amount.map { FacesBFinancialFormatting.compact($0, currency: currency, narrow: narrow) } ?? emptyValue,
                    size: fullValue == nil ? .small : narrow ? .medium : .large,
                    valueColor: FacesBFinancialFormatting.stateColor(amount),
                    trailing: layout == .standard && !narrow && fullValue != nil ? context : nil)
            .moduleInsets()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(fullValue.map { "\(metric) \($0), \(context)" } ?? emptyValue)
            .help(fullValue.map { "\(title) · \(metric) · \($0) · \(context)" } ?? "Open to connect or review saved data")
    }
}
