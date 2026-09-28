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

private struct ShopifyCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: ShopifySnapshot? { configuration.shopifySnapshot }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "bag.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(shopifyColor(configuration.shopifyColor))
            if let snapshot {
                Text(ShopifyMetricFormatter.text(for: configuration.shopifyMetric, snapshot: snapshot))
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(configuration.shopifyMetric.title).font(.system(size: 7, weight: .medium)).lineLimit(1)
                if Date.now.timeIntervalSince(snapshot.fetchedAt) > 300 {
                    Circle().fill(.orange).frame(width: 4, height: 4)
                }
            } else {
                Text("Connect").font(.system(size: 8, weight: .medium)).lineLimit(1)
            }
        }
        .frame(width: 54, height: 54)
        .help(snapshot.map { "\(configuration.shopifyDisplayName) · \(configuration.shopifyMetric.title) · Updated \($0.fetchedAt.formatted(date: .omitted, time: .shortened))" }
            ?? "Shopify · Connect an organization store")
    }
}

private struct ShopifyPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var connectedStores: [ShopifyConnectedStore] = []
    @State private var accountNameDraft = ""
    @State private var domainDraft = ""
    @State private var clientIDDraft = ""
    @State private var clientSecretDraft = ""
    @State private var newAccountColor = DockProfileColor.green.rawValue
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var isDisconnectConfirmationPresented = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: ShopifySnapshot? { configuration.shopifySnapshot }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bag.fill").foregroundStyle(shopifyColor(configuration.shopifyColor))
                    TextField("Store name", text: displayNameBinding).textFieldStyle(.plain).font(.headline)
                    Spacer(minLength: 4)
                    Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing || configuration.shopifyStoreID.isEmpty)
                    if isRefreshing { ProgressView().controlSize(.small) }
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
                            .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
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
                Text("Order value uses Shopify's current order total after returns and discounts, including tax and shipping. Unpaid and fully returned orders count; test and canceled orders do not. This is order activity, not cash received.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 375, alignment: .leading)
            .frame(minHeight: 220, alignment: .topLeading)
        }
        .frame(width: 385, height: 480)
        .task(id: "\(configuration.shopifyStoreID)|\(configuration.shopifyPeriod.rawValue)") {
            guard !configuration.shopifyStoreID.isEmpty else { return }
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: 300) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        .onAppear(perform: reloadStores)
        .confirmationDialog("Disconnect \(configuration.shopifyDisplayName)?",
                            isPresented: $isDisconnectConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Disconnect and Remove Credentials", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the Shopify client secret and access token from this Mac's Keychain. It does not uninstall the app from Shopify.")
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                Text("Store").foregroundStyle(.secondary)
                Picker("Store", selection: accountBinding) {
                    Text("Not connected").tag("")
                    ForEach(connectedStores) { connection in Text(connection.name).tag(connection.id) }
                }.labelsHidden()
            }
            GridRow {
                Text("Metric").foregroundStyle(.secondary)
                Picker("Metric", selection: metricBinding) {
                    ForEach(ShopifyMetric.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GridRow {
                Text("Period").foregroundStyle(.secondary)
                Picker("Period", selection: periodBinding) {
                    ForEach(ShopifyPeriod.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GridRow {
                Text("Color").foregroundStyle(.secondary)
                Picker("Color", selection: colorBinding) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden()
            }
            GridRow {
                Text("Chart").foregroundStyle(.secondary)
                Toggle("Show chart", isOn: chartBinding).toggleStyle(.checkbox)
            }
        }
        .font(.caption)
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            Text("Connect a Shopify store").font(.caption.weight(.semibold))
            HStack(spacing: 7) {
                TextField("Store name", text: $accountNameDraft).textFieldStyle(.roundedBorder)
                Picker("Store color", selection: $newAccountColor) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().frame(width: 100)
            }
            TextField("your-store.myshopify.com", text: $domainDraft).textFieldStyle(.roundedBorder)
            TextField("App Client ID", text: $clientIDDraft).textFieldStyle(.roundedBorder)
            SecureField("App Client Secret", text: $clientSecretDraft).textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().controlSize(.small) }
                    else { Text("Connect") }
                }
                .disabled(isConnecting || domainDraft.isEmpty || clientIDDraft.isEmpty || clientSecretDraft.isEmpty)
                if !configuration.shopifyStoreID.isEmpty {
                    Button("Disconnect", role: .destructive) { isDisconnectConfirmationPresented = true }
                }
            }
            Text("Create and install a Dev Dashboard app on a store in the same organization, with read_orders only. Shopify's client credentials grant works only for stores in that organization.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func metricChart(_ snapshot: ShopifySnapshot) -> some View {
        Chart(snapshot.dailyPoints) { point in
            let value = chartValue(point, metric: configuration.shopifyMetric, snapshot: snapshot)
            LineMark(x: .value("Day", point.date), y: .value(configuration.shopifyMetric.title, value))
                .foregroundStyle(shopifyColor(configuration.shopifyColor))
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("Day", point.date), y: .value(configuration.shopifyMetric.title, value))
                .foregroundStyle(shopifyColor(configuration.shopifyColor).opacity(0.12))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .frame(height: 82)
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
        let selectedID = configuration.shopifyStoreID
        guard !isRefreshing, !selectedID.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let account = ShopifyConnectionDirectory.stores().first(where: { $0.id == selectedID }),
                  let credential = try ShopifyCredentialStore.read(storeID: selectedID) else { throw ShopifyDataError.invalidCredentials }
            let result = try await ShopifyAPIProvider().snapshot(store: account, credential: credential, period: configuration.shopifyPeriod)
            try ShopifyCredentialStore.write(result.credential, storeID: selectedID)
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                guard value.shopifyStoreID == selectedID, value.shopifyPeriod == result.snapshot.period else { return }
                value.shopifyDisplayName = value.shopifyDisplayName.isEmpty ? account.name : value.shopifyDisplayName
                value.shopifySnapshot = result.snapshot
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
        do {
            let connection = try await ShopifyAPIProvider().connect(domain: domainDraft,
                                                                     clientID: clientIDDraft,
                                                                     clientSecret: clientSecretDraft,
                                                                     color: newAccountColor)
            let requestedName = accountNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = ShopifyConnectedStore(id: connection.store.id,
                                                name: requestedName.isEmpty ? connection.store.name : requestedName,
                                                domain: connection.store.domain,
                                                timeZoneID: connection.store.timeZoneID,
                                                currency: connection.store.currency,
                                                color: connection.store.color)
            try ShopifyConnectionDirectory.save(account, credential: connection.credential)
            accountNameDraft = ""
            domainDraft = ""
            clientIDDraft = ""
            clientSecretDraft = ""
            reloadStores()
            update {
                $0.shopifyStoreID = account.id
                $0.shopifyDisplayName = account.name
                $0.shopifyColor = account.color
                $0.shopifySnapshot = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        let selectedID = configuration.shopifyStoreID
        guard !selectedID.isEmpty else { return }
        do {
            try ShopifyConnectionDirectory.remove(storeID: selectedID)
            reloadStores()
            update { $0.shopifyStoreID = ""; $0.shopifySnapshot = nil }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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
    switch DockProfileColor(rawValue: name) ?? .green {
    case .blue: .blue
    case .purple: .purple
    case .teal: .teal
    case .green: .green
    case .orange: .orange
    case .pink: .pink
    case .red: .red
    }
}
