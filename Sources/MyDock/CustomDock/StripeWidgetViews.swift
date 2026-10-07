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
        BusinessDockFace(kind: "Stripe", title: configuration.stripeDisplayName, metric: configuration.stripeMetric.title,
            amount: values.map { StripeMetricFormatter.amount(for: configuration.stripeMetric, values: $0) },
            currency: configuration.stripeMetric == .payingSubscribers ? nil : configuration.stripeCurrency,
            fullValue: values.map { StripeMetricFormatter.text(for: configuration.stripeMetric, values: $0) },
            context: configuration.stripeMetric.isPointInTime ? "Now" : configuration.stripePeriod.faceToken,
            emptyValue: configuration.stripeSnapshot != nil || !configuration.stripeAccountID.isEmpty ? "No data" : "Connect")
    }
}

private struct StripePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var isConnecting = false
    @State private var connections: [StripeConnectedAccount] = []
    @State private var showingDisconnectConfirmation = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: StripeSnapshot? { configuration.stripeSnapshot }
    private var currencyMetrics: StripeCurrencyMetrics? { snapshot?.metrics(for: configuration.stripeCurrency) }
    private var setupDraft: StripeConnectionDraft { setupDrafts.stripeDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if let currencyMetrics {
                    // A run rate or balance is read now; only revenue and net cover the chosen period.
                    let period = configuration.stripeMetric.isPointInTime ? "Now" : snapshot?.period.title ?? configuration.stripePeriod.title
                    WidgetPopoutHero(
                        value: StripeMetricFormatter.text(for: configuration.stripeMetric, values: currencyMetrics),
                        caption:
                            "\(configuration.stripeMetric.title) · \(configuration.stripeMetric.popoutUnit(currency: configuration.stripeCurrency)) · \(period)",
                        valueColor: FacesBFinancialFormatting.stateColor(StripeMetricFormatter.amount(for: configuration.stripeMetric, values: currencyMetrics))
                    )
                } else {
                    WidgetPopoutHero(
                        value: snapshot == nil ? (configuration.stripeAccountID.isEmpty ? "Connect Stripe" : "No data") : "No currency data",
                        caption: snapshot == nil && configuration.stripeAccountID.isEmpty ? "Use a restricted, read-only key." : "Choose a currency reported by this account.")
                }
                if let count = snapshot?.unsupportedSubscriptionItems, count > 0 {
                    GroupedSection {
                        GroupedRow("Subscription estimate", subtitle: "\(count) complex items excluded", symbol: "info.circle")
                    }
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
            }
            if !BusinessSetupPresentation.showsSettings(accountID: configuration.stripeAccountID, hasSavedReading: snapshot != nil) {
                connectionControls
            } else {
                WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) { controls }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The account and period identify the reading; renaming the account is cosmetic and never refetches.
        .task(id: "\(configuration.stripeAccountID)|\(configuration.stripePeriod.rawValue)") {
            guard !snapshotRendering, !configuration.stripeAccountID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadConnections)
        .confirmationDialog(
            "Disconnect \(configuration.stripeDisplayName)?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Remove Key", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the restricted key from this Mac's Keychain, disconnects every MyDock widget using it and removes their saved figures. It does not revoke the key in Stripe.")
        }
    }

    @ViewBuilder private var controls: some View {
        GroupedSection(footer: provenanceFooter) {
            GroupedRow("Account name", symbol: "pencil") {
                TextField("Account name", text: configuration.stripeAccountID.isEmpty ? connectionNameBinding : displayNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
            }
            GroupedRow("Metric") {
                Picker("Metric", selection: metricBinding) {
                    ForEach(StripeMetric.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            GroupedRow("Account") {
                Picker("Account", selection: accountBinding) {
                    Text("None").tag("")
                    if !configuration.stripeAccountID.isEmpty, !connections.contains(where: { $0.id == configuration.stripeAccountID }) {
                        Text(configuration.stripeDisplayName + " (saved)").tag(configuration.stripeAccountID)
                    }
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
                .disabled(configuration.stripeMetric.isPointInTime)
            }
        }
        .help(metricExplanation)
        connectionControls
    }

    private var provenanceFooter: String { "Stripe reports each currency without conversion." }
    private var metricExplanation: String { "Revenue is payment activity posted to the Stripe balance, less refunds and payment reversals, before fees. It includes collected tax and excludes payouts, transfers, and disputes. Net uses Stripe's transaction net after fees. Currencies are never converted. MRR/ARR estimate active and past-due fixed recurring prices; trials and metered, tiered, discounted, or tax-adjusted items are excluded." }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupedSection("Connection") {
                if !configuration.stripeAccountID.isEmpty {
                    GroupedRow("Disconnect", role: .destructive) { showingDisconnectConfirmation = true }
                } else {
                    // An account connected for another widget is offered first, so its key is never entered twice.
                    if BusinessSetupPresentation.offersExistingConnections(accountID: configuration.stripeAccountID,
                                                                           hasSavedReading: snapshot != nil, connectionCount: connections.count) {
                        GroupedRow("Account") {
                            Picker("Account", selection: accountBinding) {
                                Text("None").tag("")
                                ForEach(connections) { account in Text(account.name).tag(account.id) }
                            }
                            .labelsHidden()
                        }
                    }
                    if !BusinessSetupPresentation.showsSettings(accountID: configuration.stripeAccountID, hasSavedReading: snapshot != nil) {
                        GroupedRow("Account name") {
                            TextField("Account name", text: connectionNameBinding)
                                .textFieldStyle(.plain)
                                .disabled(isConnecting)
                        }
                    }
                    GroupedRow("Restricted key") {
                        SecureField("Restricted key (rk_live_… or rk_test_…)", text: restrictedKeyBinding)
                            .textFieldStyle(.plain)
                            .disabled(isConnecting)
                    }
                    GroupedRow("Connect", role: .button) { Task { await connect() } }
                        .disabled(isConnecting || setupDraft.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setupDraft.restrictedKey.isEmpty)
                    if isConnecting { GroupedRow("Connecting…") { ProgressView().controlSize(.small) } }
                    GroupedRow("Clear Draft", role: .button) { setupDrafts.clearDrafts(for: item.id) }
                        .disabled(isConnecting || setupDraft.isPristine)

                    if let url = URL(string: "https://docs.stripe.com/keys#limit-access") {
                        GroupedRow("Permissions") { Link("Key permissions", destination: url) }
                    }
                }
            }
        }
        .help(
            "Grant read-only Account, Balance, Balance Transactions, and Subscriptions access. MyDock never requests write access. An unfinished form stays in memory for this widget until connected or cleared; its key is never written to profile data or backups."
        )
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

    private var currencyOptions: [String] {
        let options = snapshot?.currencyCodes ?? []
        return options.contains(configuration.stripeCurrency) ? options : [configuration.stripeCurrency] + options
    }

    private var displayNameBinding: Binding<String> {
        Binding(get: { configuration.stripeDisplayName }, set: { value in
            update { $0.stripeDisplayName = String(value.prefix(80)) }
        })
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.stripeAccountID }, set: { accountID in
            guard accountID != configuration.stripeAccountID else { return }
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

    /// Opening the popout honours the coordinator's cache; the header's refresh control is the forced refresh.
    private func refresh() async {
        await store.widgetData.refresh(item: item, profileID: profileID, force: false)
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
            // Like the Connections Center: cached figures and errors from an earlier connection are dropped.
            store.widgetData.connectionsDidChange()
        } catch {
            guard !Task.isCancelled else { return }
            DiagnosticsService.shared.record(.stripeConnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let id = configuration.stripeAccountID
        guard !id.isEmpty else { return }
        do {
            try StripeConnectionDirectory.remove(accountID: id)
            reloadConnections()
            store.clearConnectionReferences(.stripe(id))
            store.widgetData.connectionsDidChange()
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

/// Compact financial values retain a full currency/count description for VoiceOver and help.
enum FacesBFinancialFormatting {
    static func compact(_ amount: Decimal, currency: String?, narrow: Bool, locale: Locale = .current) -> String {
        let number = NSDecimalNumber(decimal: amount).doubleValue
        guard number.isFinite else { return "—" }
        let magnitude = abs(number)
        let scales: [(divisor: Double, suffix: String)] = [(1, ""), (1e3, "K"), (1e6, "M"), (1e9, "B"), (1e12, "T")]
        var index = scales.lastIndex { magnitude >= $0.divisor } ?? 0
        func digits(_ index: Int) -> Int { index == 0 ? 2 : 1 }
        // Rounded first, then promoted, so a value just under a boundary never reads "1,000K".
        let factor = pow(10, Double(digits(index)))
        if index < scales.count - 1, (magnitude / scales[index].divisor * factor).rounded() / factor >= 1_000 { index += 1 }
        let scaled = magnitude / scales[index].divisor
        let style = FloatingPointFormatStyle<Double>(locale: locale).precision(.fractionLength(0...digits(index)))
        guard let currency, !narrow else { return (number < 0 ? -scaled : scaled).formatted(style) + scales[index].suffix }
        // The locale places the sign and the symbol: "-$2.4K" in en_US, "2,4K €" in de_DE.
        let formatter = currencyFormatter(currency: currency, locale: locale)
        let prefix: String = (number < 0 ? formatter.negativePrefix : formatter.positivePrefix) ?? ""
        let suffix: String = (number < 0 ? formatter.negativeSuffix : formatter.positiveSuffix) ?? ""
        return prefix + scaled.formatted(style) + scales[index].suffix + suffix
    }

    /// One currency formatter per locale and currency: every business face formats on each render.
    nonisolated(unsafe) private static let formatters: NSCache<NSString, NumberFormatter> = {
        let cache = NSCache<NSString, NumberFormatter>(); cache.countLimit = 16; return cache
    }()

    private static func currencyFormatter(currency: String, locale: Locale) -> NumberFormatter {
        let key = NSString(string: locale.identifier + "|" + currency)
        if let cached = formatters.object(forKey: key) { return cached }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatters.setObject(formatter, forKey: key)
        return formatter
    }
    static func stateColor(_ amount: Decimal?) -> Color { amount.map { $0 < 0 ? WidgetPalette.critical : Color.primary } ?? .primary }
}

struct BusinessDockFace: View {
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

extension StripePeriod {
    var faceToken: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7d"
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        }
    }
}

extension StripeMetric {
    func popoutUnit(currency: String) -> String { self == .payingSubscribers ? "subscribers" : currency }
}

/// The setup rules shared by the Stripe, Paddle and Shopify popouts.
enum BusinessSetupPresentation {
    /// An unconnected widget with no saved reading shows only its connection form, never empty settings.
    static func showsSettings(accountID: String, hasSavedReading: Bool) -> Bool {
        !accountID.isEmpty || hasSavedReading
    }
    /// The connection form offers the connections already saved on this Mac, so a second widget reuses one.
    static func offersExistingConnections(accountID: String, hasSavedReading: Bool, connectionCount: Int) -> Bool {
        !showsSettings(accountID: accountID, hasSavedReading: hasSavedReading) && connectionCount > 0
    }
}
