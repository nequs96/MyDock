import Charts
import SwiftUI

struct PaddleWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(PaddleCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(PaddlePopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct PaddleCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: PaddleSnapshot? { configuration.paddleSnapshot }

    var body: some View {
        BusinessDockFace(kind: "Paddle", title: configuration.paddleDisplayName, metric: configuration.paddleMetric.title, value: snapshot.map { PaddleMetricFormatter.text(for: configuration.paddleMetric, snapshot: $0) }, context: configuration.paddlePeriod.title)
    }
}

private struct PaddlePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var connections: [PaddleConnectedAccount] = []
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var isDisconnectConfirmationPresented = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: PaddleSnapshot? { configuration.paddleSnapshot }
    private var setupDraft: PaddleConnectionDraft { setupDrafts.paddleDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill").foregroundStyle(color(for: configuration.paddleColor))
                TextField("Account name", text: accountNameBinding)
                    .textFieldStyle(.plain).font(.headline)
                Spacer(minLength: 4)
                Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing || configuration.paddleAccountID.isEmpty)
                if isRefreshing { ProgressView().controlSize(.small) }
            }

            if let snapshot {
                Text("\(snapshot.accountName) · Paddle Billing")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
            } else {
                Label("Connect a Paddle Billing account", systemImage: "key.horizontal")
                    .font(.callout.weight(.medium))
                Text("Paddle Classic and client-side tokens are not supported. Create a current Billing API key with Metrics → Read (metrics.read).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PaddleMetricFormatter.text(for: configuration.paddleMetric, snapshot: snapshot))
                        .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                    HStack(spacing: 6) {
                        Text(configuration.paddleMetric.title)
                        Text("·")
                        Text(configuration.paddleMetric == .activeSubscribers ? "customers" : snapshot.currency)
                        Text("·")
                        Text(snapshot.period.title)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                if configuration.paddleShowsChart { metricChart(snapshot) }
            }

            controls
            connectionControls

            if let snapshot {
                HStack(spacing: 5) {
                    Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                    Text(isStale ? "Showing last successful values" : "Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    Text("· UTC")
                }
                .font(.caption2).foregroundStyle(isStale ? Color.orange : Color.gray)
                if snapshot.period != configuration.paddlePeriod {
                    Text("Last successful period: \(snapshot.period.title) · selected: \(configuration.paddlePeriod.title)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Label(snapshot == nil ? errorMessage : "Refresh failed. Showing saved data. \(errorMessage)",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            DataSourceProvenanceView(provenance: .paddle(snapshot: snapshot, localName: configuration.paddleDisplayName,
                                                         metric: configuration.paddleMetric, error: errorMessage))
            Text("Net revenue is Paddle's reported revenue after tax and fees, before refunds and chargebacks. MRR is its current recurring run rate; ARR is MRR × 12, not a cash forecast. Paddle reports its primary balance currency and UTC-day series.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 365, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .task(id: "\(configuration.paddleAccountID)|\(configuration.paddlePeriod.rawValue)|\(configuration.paddleDisplayName)") {
            guard !configuration.paddleAccountID.isEmpty else { return }
            await refresh()
        }
        .onAppear(perform: reloadConnections)
        .confirmationDialog("Disconnect \(configuration.paddleDisplayName)?",
                            isPresented: $isDisconnectConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Disconnect and Remove Key", role: .destructive) { disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the Paddle API key from this Mac's Keychain and disconnects every MyDock widget using it. It does not revoke the key in Paddle.")
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                Text("Account").foregroundStyle(.secondary)
                Picker("Account", selection: accountBinding) {
                    Text("Not connected").tag("")
                    ForEach(connections) { account in Text(account.name).tag(account.id) }
                }.labelsHidden()
            }
            GridRow {
                Text("Metric").foregroundStyle(.secondary)
                Picker("Metric", selection: metricBinding) {
                    ForEach(PaddleMetric.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GridRow {
                Text("Period").foregroundStyle(.secondary)
                Picker("Period", selection: periodBinding) {
                    ForEach(PaddlePeriod.allCases) { Text($0.title).tag($0) }
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
            Text("Connect a Paddle Billing account").font(.caption.weight(.semibold))
            HStack(spacing: 7) {
                TextField("Account name", text: connectionAccountNameBinding).textFieldStyle(DockTextFieldStyle())
                    .disabled(isConnecting)
                Picker("Account color", selection: accountColorBinding) {
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().frame(width: 100).disabled(isConnecting)
            }
            SecureField("Paddle Billing API key", text: apiKeyBinding).textFieldStyle(DockTextFieldStyle())
                .disabled(isConnecting)
            HStack {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().controlSize(.small) }
                    else { Text("Connect") }
                }
                .disabled(isConnecting || setupDraft.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setupDraft.apiKey.isEmpty)
                Button("Clear Draft") { setupDrafts.clearDrafts(for: item.id) }
                    .disabled(isConnecting || setupDraft.isPristine)
                if !configuration.paddleAccountID.isEmpty {
                    Button("Disconnect", role: .destructive) { isDisconnectConfirmationPresented = true }
                }
            }
            Text("Grant only Metrics → Read (metrics.read). Live and sandbox keys use their matching API environment.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("An unfinished form stays in memory for this widget until connected or cleared; its key is never written to profile data or backups.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
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

    private var accountColorBinding: Binding<String> {
        Binding(get: { setupDraft.color }, set: { value in
            setupDrafts.updatePaddleDraft(for: item.id) { $0.color = value }
        })
    }

    @ViewBuilder
    private func metricChart(_ snapshot: PaddleSnapshot) -> some View {
        Chart(snapshot.points) { point in
            LineMark(x: .value("Day", point.date), y: .value(configuration.paddleMetric.title, chartValue(point, metric: configuration.paddleMetric)))
                .foregroundStyle(color(for: configuration.paddleColor))
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("Day", point.date), y: .value(configuration.paddleMetric.title, chartValue(point, metric: configuration.paddleMetric)))
                .foregroundStyle(color(for: configuration.paddleColor).opacity(0.12))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .frame(height: 82)
        .accessibilityLabel("\(configuration.paddleMetric.title) by UTC day")
    }

    private var accountBinding: Binding<String> {
        Binding(get: { configuration.paddleAccountID }, set: { id in
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
    private var colorBinding: Binding<String> {
        Binding(get: { configuration.paddleColor }, set: { value in
            update { $0.paddleColor = value }
            if let account = connections.first(where: { $0.id == configuration.paddleAccountID }) {
                PaddleConnectionDirectory.update(PaddleConnectedAccount(id: account.id, name: account.name, color: value))
                reloadConnections()
            }
        })
    }
    private var accountNameBinding: Binding<String> {
        Binding(get: { configuration.paddleDisplayName }, set: { value in update { $0.paddleDisplayName = String(value.prefix(80)) } })
    }

    private var isStale: Bool {
        guard let snapshot else { return false }
        return Date.now.timeIntervalSince(snapshot.fetchedAt) > 300 || snapshot.period != configuration.paddlePeriod
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
        refreshRequestID = UUID()
        isRefreshing = false
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

    private func chartValue(_ point: PaddleMetricPoint, metric: PaddleMetric) -> Double {
        switch metric {
        case .netRevenue: NSDecimalNumber(decimal: FinancialCurrencyFormatter.majorUnits(from: point.netRevenueMinor, currency: snapshot?.currency ?? "USD")).doubleValue
        case .mrr: NSDecimalNumber(decimal: FinancialCurrencyFormatter.majorUnits(from: point.mrrMinor, currency: snapshot?.currency ?? "USD")).doubleValue
        case .arr: NSDecimalNumber(decimal: FinancialCurrencyFormatter.majorUnits(from: point.mrrMinor * 12, currency: snapshot?.currency ?? "USD")).doubleValue
        case .activeSubscribers: Double(point.activeSubscribers)
        }
    }
}

private enum PaddleMetricFormatter {
    static func text(for metric: PaddleMetric, snapshot: PaddleSnapshot) -> String {
        switch metric {
        case .netRevenue: FinancialCurrencyFormatter.text(from: snapshot.totalNetRevenueMinor, currency: snapshot.currency)
        case .mrr: FinancialCurrencyFormatter.text(from: snapshot.latestMRRMinor, currency: snapshot.currency)
        case .arr: FinancialCurrencyFormatter.text(from: snapshot.latestARRMinor, currency: snapshot.currency)
        case .activeSubscribers: snapshot.latestActiveSubscribers.formatted()
        }
    }
}

private func color(for name: String) -> Color {
    (DockProfileColor(rawValue: name) ?? .blue).displayColor
}
