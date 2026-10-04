import Charts
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
            context: configuration.shopifyPeriod.title, emptyValue: snapshot != nil || !configuration.shopifyStoreID.isEmpty ? "No data" : "Connect")
    }
}

private struct ShopifyPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var connectedStores: [ShopifyConnectedStore] = []
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var isDisconnectConfirmationPresented = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: ShopifySnapshot? { configuration.shopifySnapshot }
    private var setupDraft: ShopifyConnectionDraft { setupDrafts.shopifyDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedSection {
                GroupedRow("Store name", symbol: "pencil") {
                    TextField("Store name", text: displayNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                }
                GroupedRow("Refresh", symbol: "arrow.clockwise") {
                    Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing || configuration.shopifyStoreID.isEmpty)
                    if isRefreshing { ProgressView().controlSize(.small) }
                }
            }

            if let snapshot {
                Text("\(snapshot.storeName) · \(snapshot.storeDomain)")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
            } else {
                Label("Connect a Shopify store", systemImage: "key.horizontal")
                    .font(.callout.weight(.medium))
                Text("Use an app installed on a store in the same Shopify organization. Grant only read_orders; Shopify limits standard access to the last 60 days.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ShopifyMetricFormatter.text(for: configuration.shopifyMetric, snapshot: snapshot))
                        .font(DockDesign.Module.valueLarge)
                    HStack(spacing: 6) {
                        Text(configuration.shopifyMetric.title)
                        Text("·")
                        Text(configuration.shopifyMetric == .orders ? "orders" : snapshot.currency)
                        Text("·")
                        Text(snapshot.period.title)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                if configuration.shopifyShowsChart { metricChart(snapshot) }
                breakdowns(snapshot)
            }

            controls
            connectionControls

            if let snapshot {
                HStack(spacing: 5) {
                    Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                    Text(isStale ? "Showing last successful values" : "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    Text("· \(timeZoneLabel(snapshot.timeZoneID))")
                }
                .font(.caption2).foregroundStyle(isStale ? Color.orange : Color.gray)
                if snapshot.period != configuration.shopifyPeriod {
                    Text("Last successful period: \(snapshot.period.title) · selected: \(configuration.shopifyPeriod.title)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Label(snapshot == nil ? errorMessage : "Refresh failed. Showing saved data. \(errorMessage)",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            DataSourceProvenanceView(provenance: .shopify(snapshot: snapshot, localName: configuration.shopifyDisplayName,
                                                          error: errorMessage))
            Text("Order value uses Shopify's current order total after returns and discounts, including tax and shipping. Unpaid and fully returned orders count; test and canceled orders do not. This is order activity, not cash received.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(configuration.shopifyStoreID)|\(configuration.shopifyPeriod.rawValue)|\(configuration.shopifyDisplayName)") {
            guard !configuration.shopifyStoreID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadStores)
        .confirmationDialog("Disconnect \(configuration.shopifyDisplayName)?",
                            isPresented: $isDisconnectConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Disconnect and Remove Credentials", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the Shopify client secret and access token from this Mac's Keychain and disconnects every MyDock widget using them. It does not uninstall the app from Shopify.")
        }
    }

    private var controls: some View {
        GroupedSection("Display") {
            GroupedRow("Store") {
                Picker("Store", selection: accountBinding) {
                    Text("Not connected").tag("")
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
            GroupedRow("Color") {
                Picker("Color", selection: colorBinding) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden()
            }
            GroupedRow("Show chart", symbol: "chart.xyaxis.line", isOn: chartBinding)
        }
        .font(.caption)
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupedSection("Connect a Shopify store") {
                GroupedRow("Store name") {
                    TextField("Store name", text: accountNameBinding).textFieldStyle(DockTextFieldStyle())
                        .disabled(isConnecting)
                }
                GroupedRow("Store color") {
                    Picker("Store color", selection: accountColorBinding) {
                        ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                    }.labelsHidden().disabled(isConnecting)
                }
                GroupedRow("Domain") {
                    TextField("your-store.myshopify.com", text: domainBinding).textFieldStyle(DockTextFieldStyle()).disabled(isConnecting)
                }
                GroupedRow("Client ID") {
                    TextField("App Client ID", text: clientIDBinding).textFieldStyle(DockTextFieldStyle()).disabled(isConnecting)
                }
                GroupedRow("Client secret") {
                    SecureField("App Client Secret", text: clientSecretBinding).textFieldStyle(DockTextFieldStyle()).disabled(isConnecting)
                }
                GroupedRow("Connect", role: .button) { Task { await connect() } }
                    .disabled(isConnecting || setupDraft.domain.isEmpty || setupDraft.clientID.isEmpty || setupDraft.clientSecret.isEmpty)
                if isConnecting { GroupedRow("Connecting…") { ProgressView().controlSize(.small) } }
                GroupedRow("Clear Draft", role: .button) { setupDrafts.clearDrafts(for: item.id) }
                    .disabled(isConnecting || setupDraft.isPristine)
                if !configuration.shopifyStoreID.isEmpty {
                    GroupedRow("Disconnect", role: .destructive) { isDisconnectConfirmationPresented = true }
                }
            }
            Text("Create and install a Dev Dashboard app on a store in the same organization, with read_orders only. Shopify's client credentials grant works only for stores in that organization.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("An unfinished form stays in memory for this widget until connected or cleared; the client secret is never written to profile data or backups.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
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

    private var accountColorBinding: Binding<String> {
        Binding(get: { setupDraft.color }, set: { value in
            setupDrafts.updateShopifyDraft(for: item.id) { $0.color = value }
        })
    }

    @ViewBuilder
    private func metricChart(_ snapshot: ShopifySnapshot) -> some View {
        MicroSparkline(values: snapshot.dailyPoints.map { chartValue($0, metric: configuration.shopifyMetric, snapshot: snapshot) }, color: .secondary)
            .frame(height: 82)
            .accessibilityHidden(false)
            .accessibilityLabel("\(configuration.shopifyMetric.title) by store-local day")
    }

    @ViewBuilder
    private func breakdowns(_ snapshot: ShopifySnapshot) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Units by product").font(.caption.weight(.semibold))
                if snapshot.productBreakdown.isEmpty {
                    Text("No product details in this period").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.productBreakdown.prefix(5)) { row in
                        HStack {
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 5)
                            Text(row.units.formatted()).monospacedDigit()
                        }.font(.caption2)
                    }
                }
                if snapshot.productBreakdownIncompleteOrders > 0 {
                    Text("Some orders contain over 250 line items; product counts are incomplete.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Order traffic").font(.caption.weight(.semibold))
                if snapshot.trafficBreakdown.isEmpty {
                    Text("Shopify provided no attribution for this period.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.trafficBreakdown.prefix(5)) { row in
                        HStack {
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 5)
                            Text(row.orders.formatted()).monospacedDigit()
                        }.font(.caption2)
                    }
                    Text("Attributed orders: \(snapshot.trafficAttributedOrders) of \(snapshot.orderCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.shopifyStoreID }, set: { id in
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
    private var colorBinding: Binding<String> {
        Binding(get: { configuration.shopifyColor }, set: { value in
            update { $0.shopifyColor = value }
            if let selected = connectedStores.first(where: { $0.id == configuration.shopifyStoreID }) {
                ShopifyConnectionDirectory.update(ShopifyConnectedStore(id: selected.id, name: selected.name, domain: selected.domain,
                                                                        timeZoneID: selected.timeZoneID, currency: selected.currency, color: value))
                reloadStores()
            }
        })
    }
    private var displayNameBinding: Binding<String> {
        Binding(get: { configuration.shopifyDisplayName }, set: { value in update { $0.shopifyDisplayName = String(value.prefix(80)) } })
    }

    private var isStale: Bool {
        guard let snapshot else { return false }
        return Date.now.timeIntervalSince(snapshot.fetchedAt) > 300 || snapshot.period != configuration.shopifyPeriod
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
    private func chartValue(_ point: ShopifyDailyPoint, metric: ShopifyMetric, snapshot: ShopifySnapshot) -> Double {
        switch metric {
        case .orderValue: return NSDecimalNumber(decimal: point.orderValue).doubleValue
        case .orders: return Double(point.orders)
        case .averageOrderValue:
            guard point.orders > 0 else { return 0 }
            return NSDecimalNumber(decimal: point.orderValue / Decimal(point.orders)).doubleValue
        }
    }
    private func timeZoneLabel(_ id: String) -> String {
        TimeZone(identifier: id)?.abbreviation() ?? id
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

private func shopifyColor(_ name: String) -> Color {
    (DockProfileColor(rawValue: name) ?? .green).displayColor
}
