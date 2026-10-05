import SwiftUI

struct ShopifyWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(ShopifyCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(ShopifyPopoutView(store: store, item: item, profileID: profileID))
    }
}

struct ShopifyCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: ShopifySnapshot? { configuration.shopifySnapshot }

    var body: some View {
        FacesBBusinessDockFace(kind: "Shopify", title: configuration.shopifyDisplayName, metric: configuration.shopifyMetric.title,
            amount: snapshot.flatMap { ShopifyMetricFormatter.amount(for: configuration.shopifyMetric, snapshot: $0) },
            currency: configuration.shopifyMetric == .orders ? nil : snapshot?.currency,
            fullValue: snapshot.map { ShopifyMetricFormatter.text(for: configuration.shopifyMetric, snapshot: $0) },
            context: configuration.shopifyPeriod.faceToken, emptyValue: snapshot != nil || !configuration.shopifyStoreID.isEmpty ? "No data" : "Connect")
    }
}

private struct ShopifyPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var connectedStores: [ShopifyConnectedStore] = []
    @State private var isConnecting = false
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var isDisconnectConfirmationPresented = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: ShopifySnapshot? { configuration.shopifySnapshot }
    private var setupDraft: ShopifyConnectionDraft { setupDrafts.shopifyDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if let snapshot {
                    WidgetPopoutHero(
                        value: ShopifyMetricFormatter.text(for: configuration.shopifyMetric, snapshot: snapshot),
                        caption: "\(configuration.shopifyMetric.title) · \(configuration.shopifyMetric.popoutUnit(currency: snapshot.currency)) · \(snapshot.period.title)")
                    if configuration.shopifyShowsChart { metricChart(snapshot) }
                    breakdowns(snapshot)
                } else {
                    WidgetPopoutHero(
                        value: configuration.shopifyStoreID.isEmpty ? "Connect Shopify" : "No data",
                        caption: "Store order activity · read_orders access")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
            }
            if !ShopifySetupPresentation.showsSettings(accountID: configuration.shopifyStoreID, hasSavedReading: snapshot != nil) {
                connectionControls
            } else {
                WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) { controls }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(configuration.shopifyStoreID)|\(configuration.shopifyPeriod.rawValue)|\(configuration.shopifyDisplayName)") {
            guard !snapshotRendering, !configuration.shopifyStoreID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadStores)
        .confirmationDialog(
            "Disconnect \(configuration.shopifyDisplayName)?",
            isPresented: $isDisconnectConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Remove Credentials", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the Shopify client secret and access token from this Mac's Keychain and disconnects every MyDock widget using them. It does not uninstall the app from Shopify."
            )
        }
    }

    @ViewBuilder private var controls: some View {
        GroupedSection(footer: provenanceFooter) {
            GroupedRow("Store name", symbol: "pencil") {
                TextField("Store name", text: configuration.shopifyStoreID.isEmpty ? accountNameBinding : displayNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
            }
            GroupedRow("Store") {
                Picker("Store", selection: accountBinding) {
                    Text(snapshot == nil ? "Not connected" : "Saved reading only").tag("")
                    if !configuration.shopifyStoreID.isEmpty, !connectedStores.contains(where: { $0.id == configuration.shopifyStoreID }) {
                        Text(configuration.shopifyDisplayName + " (saved)").tag(configuration.shopifyStoreID)
                    }
                    ForEach(connectedStores) { connection in Text(connection.name).tag(connection.id) }
                }.labelsHidden()
            }
            GroupedRow("Metric") {
                Picker("Metric", selection: metricBinding) {
                    ForEach(ShopifyMetric.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GroupedRow("Period") {
                Picker("Period", selection: periodBinding) {
                    ForEach(ShopifyPeriod.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }

            GroupedRow("Show chart", symbol: "chart.xyaxis.line", isOn: chartBinding)

        }
        .help(metricExplanation)
        connectionControls
    }

    private var provenanceFooter: String { "Shopify reports order activity, not cash received." }
    private var metricExplanation: String { "Order value uses Shopify's current order total after returns and discounts, including tax and shipping. Unpaid and fully returned orders count; test and canceled orders do not. This is order activity, not cash received." }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupedSection("Connection") {
                if !configuration.shopifyStoreID.isEmpty {
                    GroupedRow("Disconnect", role: .destructive) { isDisconnectConfirmationPresented = true }
                } else {
                    if !ShopifySetupPresentation.showsSettings(accountID: configuration.shopifyStoreID, hasSavedReading: snapshot != nil) {
                        GroupedRow("Store name") {
                            TextField("Store name", text: accountNameBinding).textFieldStyle(.plain)
                                .disabled(isConnecting)
                        }
                    }
                    GroupedRow("Domain") {
                        TextField("your-store.myshopify.com", text: domainBinding).textFieldStyle(.plain).disabled(isConnecting)
                    }
                    GroupedRow("Client ID") {
                        TextField("App Client ID", text: clientIDBinding).textFieldStyle(.plain).disabled(isConnecting)
                    }
                    GroupedRow("Client secret") {
                        SecureField("App Client Secret", text: clientSecretBinding).textFieldStyle(.plain).disabled(isConnecting)
                    }
                    GroupedRow("Connect", role: .button) { Task { await connect() } }
                        .disabled(isConnecting || setupDraft.domain.isEmpty || setupDraft.clientID.isEmpty || setupDraft.clientSecret.isEmpty)
                    if isConnecting { GroupedRow("Connecting…") { ProgressView().controlSize(.small) } }
                    GroupedRow("Clear Draft", role: .button) { setupDrafts.clearDrafts(for: item.id) }
                        .disabled(isConnecting || setupDraft.isPristine)
                }
            }
        }
        .help(
            "Create and install a Dev Dashboard app on a store in the same organization, with read_orders only. Shopify's client credentials grant works only for stores in that organization. An unfinished form stays in memory for this widget until connected or cleared; the client secret is never written to profile data or backups."
        )
    }

    private var accountNameBinding: Binding<String> {
        Binding(get: { setupDraft.accountName }, set: { value in
            setupDrafts.updateShopifyDraft(for: item.id) { $0.accountName = String(value.prefix(80)) }
        })
    }

    private var domainBinding: Binding<String> {
        Binding(get: { setupDraft.domain }, set: { value in
            setupDrafts.updateShopifyDraft(for: item.id) { $0.domain = value }
        })
    }

    private var clientIDBinding: Binding<String> {
        Binding(get: { setupDraft.clientID }, set: { value in
            setupDrafts.updateShopifyDraft(for: item.id) { $0.clientID = value }
        })
    }

    private var clientSecretBinding: Binding<String> {
        Binding(get: { setupDraft.clientSecret }, set: { value in
            setupDrafts.updateShopifyDraft(for: item.id) { $0.clientSecret = value }
        })
    }

    @ViewBuilder
    private func metricChart(_ snapshot: ShopifySnapshot) -> some View {
        let series = ShopifyChartAccessibility.series(snapshot, metric: configuration.shopifyMetric)
        ZStack {
            MicroSparkline(values: series.map(\.value), color: .secondary)
        }
        .frame(height: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(configuration.shopifyMetric.title) by store-local day")
        .accessibilityValue(FacesBChartAccessibility.valueList(series,
            timeZone: TimeZone(identifier: snapshot.timeZoneID) ?? TimeZone(secondsFromGMT: 0)!,
            currency: configuration.shopifyMetric == .orders ? nil : snapshot.currency))
    }

    @ViewBuilder
    private func breakdowns(_ snapshot: ShopifySnapshot) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Units by product").font(DockDesign.Grouped.subtitleFont.weight(.semibold))
                if snapshot.productBreakdown.isEmpty {
                    Text("No product details in this period").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.productBreakdown.prefix(5)) { row in
                        HStack {
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 5)
                            Text(row.units.formatted()).monospacedDigit()
                        }.font(DockDesign.Grouped.subtitleFont)
                    }
                }
                if snapshot.productBreakdownIncompleteOrders > 0 {
                    Text("Some orders contain over 250 line items; product counts are incomplete.")
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Order traffic").font(DockDesign.Grouped.subtitleFont.weight(.semibold))
                if snapshot.trafficBreakdown.isEmpty {
                    Text("Shopify provided no attribution for this period.").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.trafficBreakdown.prefix(5)) { row in
                        HStack {
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 5)
                            Text(row.orders.formatted()).monospacedDigit()
                        }.font(DockDesign.Grouped.subtitleFont)
                    }
                    Text("Attributed orders: \(snapshot.trafficAttributedOrders) of \(snapshot.orderCount)")
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.shopifyStoreID }, set: { id in
            guard id != configuration.shopifyStoreID else { return }
            guard let connection = connectedStores.first(where: { $0.id == id }) else {
                update { $0.shopifyStoreID = ""; $0.shopifySnapshot = nil }
                return
            }
            update {
                $0.shopifyStoreID = connection.id
                $0.shopifyDisplayName = connection.name
                $0.shopifyColor = connection.color
                $0.shopifySnapshot = nil
            }
            errorMessage = nil
        })
    }
    private var metricBinding: Binding<ShopifyMetric> {
        Binding(get: { configuration.shopifyMetric }, set: { value in update { $0.shopifyMetric = value } })
    }
    private var periodBinding: Binding<ShopifyPeriod> {
        Binding(get: { configuration.shopifyPeriod }, set: { value in update { $0.shopifyPeriod = value } })
    }
    private var chartBinding: Binding<Bool> {
        Binding(get: { configuration.shopifyShowsChart }, set: { value in update { $0.shopifyShowsChart = value } })
    }

    private var displayNameBinding: Binding<String> {
        Binding(get: { configuration.shopifyDisplayName }, set: { value in update { $0.shopifyDisplayName = String(value.prefix(80)) } })
    }

    private func refresh() async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID)
        guard refreshRequestID == requestID, !Task.isCancelled else { return }
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        errorMessage = nil
        let draft = setupDraft
        do {
            let connection = try await ShopifyAPIProvider().connect(domain: draft.domain,
                                                                     clientID: draft.clientID,
                                                                     clientSecret: draft.clientSecret,
                                                                     color: draft.color)
            let requestedName = draft.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = ShopifyConnectedStore(id: connection.store.id,
                                                name: requestedName.isEmpty ? connection.store.name : requestedName,
                                                domain: connection.store.domain,
                                                timeZoneID: connection.store.timeZoneID,
                                                currency: connection.store.currency,
                                                color: connection.store.color)
            guard !Task.isCancelled,
                  let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
                    .first(where: { $0.id == item.id && $0.widgetKind == "Shopify" }),
                  (currentItem.widgetConfiguration ?? WidgetConfiguration()).shopifyStoreID.isEmpty else { return }
            try ShopifyConnectionDirectory.save(account, credential: connection.credential)
            setupDrafts.clearDrafts(for: item.id)
            reloadStores()
            update {
                $0.shopifyStoreID = account.id
                $0.shopifyDisplayName = account.name
                $0.shopifyColor = account.color
                $0.shopifySnapshot = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiagnosticsService.shared.record(.shopifyConnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let selectedID = configuration.shopifyStoreID
        guard !selectedID.isEmpty else { return }
        refreshRequestID = UUID()
        isRefreshing = false
        do {
            try ShopifyConnectionDirectory.remove(storeID: selectedID)
            reloadStores()
            store.clearConnectionReferences(.shopify(selectedID))
            errorMessage = nil
        } catch {
            DiagnosticsService.shared.record(.shopifyDisconnectionFailed)
            errorMessage = error.localizedDescription
        }
    }

    private func reloadStores() { connectedStores = ShopifyConnectionDirectory.stores() }
    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }

}

private enum ShopifyMetricFormatter {
    static func amount(for metric: ShopifyMetric, snapshot: ShopifySnapshot) -> Decimal? {
        switch metric {
        case .orderValue: snapshot.orderValue
        case .orders: Decimal(snapshot.orderCount)
        case .averageOrderValue: snapshot.averageOrderValue
        }
    }

    static func text(for metric: ShopifyMetric, snapshot: ShopifySnapshot) -> String {
        switch metric {
        case .orderValue: snapshot.orderValue.formatted(.currency(code: snapshot.currency))
        case .orders: snapshot.orderCount.formatted()
        case .averageOrderValue:
            snapshot.averageOrderValue?.formatted(.currency(code: snapshot.currency)) ?? "—"
        }
    }
}

extension ShopifyPeriod {
    var faceToken: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7d"
        case .thirtyDays: "30d"
        case .monthToDate: "MTD"
        }
    }
}

enum ShopifyChartAccessibility {
    static func series(_ snapshot: ShopifySnapshot, metric: ShopifyMetric) -> [FacesBDatedChartValue] {
        snapshot.dailyPoints.map { point in
            let value: Decimal
            switch metric {
            case .orderValue: value = point.orderValue
            case .orders: value = Decimal(point.orders)
            case .averageOrderValue: value = point.orders > 0 ? point.orderValue / Decimal(point.orders) : 0
            }
            return FacesBDatedChartValue(date: point.date, value: NSDecimalNumber(decimal: value).doubleValue)
        }
    }
}

extension ShopifyMetric {
    func popoutUnit(currency: String) -> String { self == .orders ? "orders" : currency }
}

enum ShopifySetupPresentation {
    static func showsSettings(accountID: String, hasSavedReading: Bool) -> Bool {
        !accountID.isEmpty || hasSavedReading
    }
}
