import SwiftUI

struct PaddleWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(PaddleCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(PaddlePopoutView(store: store, item: item, profileID: profileID))
    }
}

struct PaddleCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: PaddleSnapshot? { configuration.paddleSnapshot }

    var body: some View {
        FacesBBusinessDockFace(kind: "Paddle", title: configuration.paddleDisplayName, metric: configuration.paddleMetric.title,
            amount: snapshot.map { PaddleMetricFormatter.amount(for: configuration.paddleMetric, snapshot: $0) },
            currency: configuration.paddleMetric == .activeSubscribers ? nil : snapshot?.currency,
            fullValue: snapshot.map { PaddleMetricFormatter.text(for: configuration.paddleMetric, snapshot: $0) },
            context: configuration.paddlePeriod.faceToken, emptyValue: configuration.paddleAccountID.isEmpty ? "Connect" : "No data")
    }
}

private struct PaddlePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var connections: [PaddleConnectedAccount] = []
    @State private var isConnecting = false
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var isDisconnectConfirmationPresented = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: PaddleSnapshot? { configuration.paddleSnapshot }
    private var setupDraft: PaddleConnectionDraft { setupDrafts.paddleDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if let snapshot {
                    WidgetPopoutHero(
                        value: PaddleMetricFormatter.text(for: configuration.paddleMetric, snapshot: snapshot),
                        caption: "\(configuration.paddleMetric.title) · \(configuration.paddleMetric.popoutUnit(currency: snapshot.currency)) · \(snapshot.period.title)")
                    if configuration.paddleShowsChart { metricChart(snapshot) }
                } else {
                    WidgetPopoutHero(
                        value: configuration.paddleAccountID.isEmpty ? "Connect Paddle" : "No data",
                        caption: "Paddle Billing · Metrics read access")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
            }
            if !BusinessSetupPresentation.showsSettings(accountID: configuration.paddleAccountID, hasSavedReading: snapshot != nil) {
                connectionControls
            } else {
                WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) { controls }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The account and period identify the reading; renaming the account is cosmetic and never refetches.
        .task(id: "\(configuration.paddleAccountID)|\(configuration.paddlePeriod.rawValue)") {
            guard !snapshotRendering, !configuration.paddleAccountID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadConnections)
        .confirmationDialog(
            "Disconnect \(configuration.paddleDisplayName)?",
            isPresented: $isDisconnectConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Remove Key", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Paddle API key from this Mac's Keychain, disconnects every MyDock widget using it and removes their saved figures. It does not revoke the key in Paddle.")
        }
    }

    @ViewBuilder private var controls: some View {
        GroupedSection(footer: provenanceFooter) {
            GroupedRow("Account name", symbol: "pencil") {
                TextField("Account name", text: configuration.paddleAccountID.isEmpty ? connectionAccountNameBinding : accountNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
            }
            GroupedRow("Account") {
                Picker("Account", selection: accountBinding) {
                    Text("None").tag("")
                    if !configuration.paddleAccountID.isEmpty, !connections.contains(where: { $0.id == configuration.paddleAccountID }) {
                        Text(configuration.paddleDisplayName + " (saved)").tag(configuration.paddleAccountID)
                    }
                    ForEach(connections) { account in Text(account.name).tag(account.id) }
                }.labelsHidden()
            }
            GroupedRow("Metric") {
                Picker("Metric", selection: metricBinding) {
                    ForEach(PaddleMetric.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GroupedRow("Period") {
                Picker("Period", selection: periodBinding) {
                    ForEach(PaddlePeriod.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }

            GroupedRow("Show chart", symbol: "chart.xyaxis.line", isOn: chartBinding)

        }
        .help(metricExplanation)
        connectionControls
    }

    private var provenanceFooter: String { "Paddle reports its balance currency by UTC day." }
    private var metricExplanation: String { "Net revenue is Paddle's reported revenue after tax and fees, before refunds and chargebacks. MRR is its current recurring run rate; ARR is MRR × 12, not a cash forecast. Paddle reports its primary balance currency and UTC-day series." }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupedSection("Connection") {
                if !configuration.paddleAccountID.isEmpty {
                    GroupedRow("Disconnect", role: .destructive) { isDisconnectConfirmationPresented = true }
                } else {
                    // An account connected for another widget is offered first, so its key is never entered twice.
                    if BusinessSetupPresentation.offersExistingConnections(accountID: configuration.paddleAccountID,
                                                                           hasSavedReading: snapshot != nil, connectionCount: connections.count) {
                        GroupedRow("Account") {
                            Picker("Account", selection: accountBinding) {
                                Text("None").tag("")
                                ForEach(connections) { account in Text(account.name).tag(account.id) }
                            }
                            .labelsHidden()
                        }
                    }
                    if !BusinessSetupPresentation.showsSettings(accountID: configuration.paddleAccountID, hasSavedReading: snapshot != nil) {
                        GroupedRow("Account name") {
                            TextField("Account name", text: connectionAccountNameBinding).textFieldStyle(.plain)
                                .disabled(isConnecting)
                        }
                    }
                    GroupedRow("API key") {
                        SecureField("Paddle Billing API key", text: apiKeyBinding).textFieldStyle(.plain)
                            .disabled(isConnecting)
                    }
                    GroupedRow("Connect", role: .button) { Task { await connect() } }
                        .disabled(isConnecting || setupDraft.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setupDraft.apiKey.isEmpty)
                    if isConnecting { GroupedRow("Connecting…") { ProgressView().controlSize(.small) } }
                    GroupedRow("Clear Draft", role: .button) { setupDrafts.clearDrafts(for: item.id) }
                        .disabled(isConnecting || setupDraft.isPristine)
                }
            }
        }
        .help(
            "Grant only Metrics → Read (metrics.read). Live and sandbox keys use their matching API environment. An unfinished form stays in memory for this widget until connected or cleared; its key is never written to profile data or backups."
        )
    }

    private var connectionAccountNameBinding: Binding<String> {
        Binding(get: { setupDraft.accountName }, set: { value in
            setupDrafts.updatePaddleDraft(for: item.id) { $0.accountName = String(value.prefix(80)) }
        })
    }

    private var apiKeyBinding: Binding<String> {
        Binding(get: { setupDraft.apiKey }, set: { value in
            setupDrafts.updatePaddleDraft(for: item.id) { $0.apiKey = value }
        })
    }

    @ViewBuilder
    private func metricChart(_ snapshot: PaddleSnapshot) -> some View {
        let series = PaddleChartAccessibility.series(snapshot, metric: configuration.paddleMetric)
        ZStack {
            MicroSparkline(values: series.map(\.value), color: .secondary)
        }
        .frame(height: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(configuration.paddleMetric.title) by UTC day")
        .accessibilityValue(FacesBChartAccessibility.valueList(series, timeZone: TimeZone(secondsFromGMT: 0)!,
            currency: configuration.paddleMetric == .activeSubscribers ? nil : snapshot.currency))
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.paddleAccountID }, set: { id in
            guard id != configuration.paddleAccountID else { return }
            guard let account = connections.first(where: { $0.id == id }) else {
                update { $0.paddleAccountID = ""; $0.paddleSnapshot = nil }
                return
            }
            update {
                $0.paddleAccountID = account.id
                $0.paddleDisplayName = account.name
                $0.paddleColor = account.color
                $0.paddleSnapshot = nil
            }
            errorMessage = nil
        })
    }

    private var metricBinding: Binding<PaddleMetric> {
        Binding(get: { configuration.paddleMetric }, set: { value in update { $0.paddleMetric = value } })
    }
    private var periodBinding: Binding<PaddlePeriod> {
        Binding(get: { configuration.paddlePeriod }, set: { value in update { $0.paddlePeriod = value } })
    }
    private var chartBinding: Binding<Bool> {
        Binding(get: { configuration.paddleShowsChart }, set: { value in update { $0.paddleShowsChart = value } })
    }

    private var accountNameBinding: Binding<String> {
        Binding(get: { configuration.paddleDisplayName }, set: { value in update { $0.paddleDisplayName = String(value.prefix(80)) } })
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
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = draft.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await PaddleAPIProvider().validate(apiKey: key)
            guard !Task.isCancelled,
                  let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
                    .first(where: { $0.id == item.id && $0.widgetKind == "Paddle" }),
                  (currentItem.widgetConfiguration ?? WidgetConfiguration()).paddleAccountID.isEmpty else { return }
            let account = PaddleConnectedAccount(name: name, color: draft.color)
            try PaddleConnectionDirectory.save(account, key: key)
            setupDrafts.clearDrafts(for: item.id)
            reloadConnections()
            update {
                $0.paddleAccountID = account.id
                $0.paddleDisplayName = account.name
                $0.paddleColor = account.color
                $0.paddleSnapshot = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiagnosticsService.shared.record(.paddleConnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let selectedID = configuration.paddleAccountID
        guard !selectedID.isEmpty else { return }
        do {
            try PaddleConnectionDirectory.remove(accountID: selectedID)
            reloadConnections()
            store.clearConnectionReferences(.paddle(selectedID))
            errorMessage = nil
        } catch {
            DiagnosticsService.shared.record(.paddleDisconnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func reloadConnections() { connections = PaddleConnectionDirectory.accounts() }
    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }

}

private enum PaddleMetricFormatter {
    static func amount(for metric: PaddleMetric, snapshot: PaddleSnapshot) -> Decimal {
        let minor: Decimal
        switch metric {
        case .activeSubscribers: return Decimal(snapshot.latestActiveSubscribers)
        case .netRevenue: minor = snapshot.totalNetRevenueMinor
        case .mrr: minor = snapshot.latestMRRMinor
        case .arr: minor = snapshot.latestARRMinor
        }
        return FinancialCurrencyFormatter.majorUnits(from: minor, currency: snapshot.currency)
    }

    static func text(for metric: PaddleMetric, snapshot: PaddleSnapshot) -> String {
        switch metric {
        case .netRevenue: FinancialCurrencyFormatter.text(from: snapshot.totalNetRevenueMinor, currency: snapshot.currency)
        case .mrr: FinancialCurrencyFormatter.text(from: snapshot.latestMRRMinor, currency: snapshot.currency)
        case .arr: FinancialCurrencyFormatter.text(from: snapshot.latestARRMinor, currency: snapshot.currency)
        case .activeSubscribers: snapshot.latestActiveSubscribers.formatted()
        }
    }
}

extension PaddlePeriod {
    var faceToken: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7d"
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        }
    }
}

struct FacesBDatedChartValue: Equatable {
    var date: Date
    var value: Double
}

enum FacesBChartAccessibility {
    static func valueList(_ series: [FacesBDatedChartValue], timeZone: TimeZone, currency: String?, locale: Locale = .current) -> String {
        series.map { point in
            let day = point.date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: timeZone))
            let value = currency.map { point.value.formatted(.currency(code: $0).locale(locale)) }
                ?? point.value.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
            return "\(day): \(value)"
        }.joined(separator: "; ")
    }
}

enum PaddleChartAccessibility {
    static func series(_ snapshot: PaddleSnapshot, metric: PaddleMetric) -> [FacesBDatedChartValue] {
        snapshot.points.map { point in
            let value: Decimal
            switch metric {
            case .activeSubscribers: value = Decimal(point.activeSubscribers)
            case .netRevenue: value = FinancialCurrencyFormatter.majorUnits(from: point.netRevenueMinor, currency: snapshot.currency)
            case .mrr: value = FinancialCurrencyFormatter.majorUnits(from: point.mrrMinor, currency: snapshot.currency)
            case .arr: value = FinancialCurrencyFormatter.majorUnits(from: point.mrrMinor * 12, currency: snapshot.currency)
            }
            return FacesBDatedChartValue(date: point.date, value: NSDecimalNumber(decimal: value).doubleValue)
        }
    }
}

extension PaddleMetric {
    func popoutUnit(currency: String) -> String { self == .activeSubscribers ? "customers" : currency }
}

