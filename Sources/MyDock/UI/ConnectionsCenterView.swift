import SwiftUI

/// The business services a connection belongs to. The raw value is the widget kind it serves.
enum ConnectionKind: String, CaseIterable, Identifiable, Sendable {
    case stripe = "Stripe", paddle = "Paddle", shopify = "Shopify"

    var id: Self { self }
    var title: String { rawValue }
    var symbol: String { self == .shopify ? "bag" : "creditcard" }
    func reference(_ identifier: String) -> WidgetConnectionReference {
        switch self {
        case .stripe: .stripe(identifier)
        case .paddle: .paddle(identifier)
        case .shopify: .shopify(identifier)
        }
    }
}

/// Why connecting or replacing credentials stopped before anything was saved.
enum ConnectionError: LocalizedError, Equatable {
    case differentShopifyStore
    case changedWhileTesting

    var errorDescription: String? {
        switch self {
        case .differentShopifyStore: "This is a different Shopify store. Cancel replacement and add it as a separate connection."
        case .changedWhileTesting: "This connection changed or was removed while testing. Its credentials were left untouched."
        }
    }
}

struct ConnectionsCenterView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    init(store: ProfileStore) {
        self.store = store
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    @State private var provider = ConnectionKind.stripe
    @State private var name = ""
    @State private var secret = ""
    @State private var domain = ""
    @State private var clientID = ""
    @State private var replacingID: String?
    @State private var revision = 0
    @State private var busy = false
    @State private var message: String?
    @State private var connectionFormExpanded = false
    @State private var pendingDisconnect: ConnectionRow?

    private struct ConnectionRow: Identifiable {
        var kind: ConnectionKind
        var identifier: String
        var name: String
        var id: String { kind.rawValue + identifier }
        var reference: WidgetConnectionReference { kind.reference(identifier) }
    }

    private var rows: [ConnectionRow] {
        _ = revision
        return StripeConnectionDirectory.accounts().map { ConnectionRow(kind: .stripe, identifier: $0.id, name: $0.name) }
            + PaddleConnectionDirectory.accounts().map { ConnectionRow(kind: .paddle, identifier: $0.id, name: $0.name) }
            + ShopifyConnectionDirectory.stores().map { ConnectionRow(kind: .shopify, identifier: $0.id, name: $0.name) }
    }

    /// Every widget configuration in every Dock, read once per render and shared by the rows.
    private func widgetConfigurations() -> [WidgetConfiguration] {
        store.state.profiles.map { store.presentationProfile($0) }.flatMap(\.items).compactMap { $0.widgetConfiguration }
    }

    /// Newest stored reading among widgets assigned to this connection; nothing is fetched here.
    private func provenance(for row: ConnectionRow, items: [WidgetConfiguration]) -> DataSourceProvenance {
        switch row.kind {
        case .stripe:
            let match = items.filter { $0.stripeAccountID == row.identifier }
            let latest = match.compactMap { c in c.stripeSnapshot.map { (c, $0) } }.max { $0.1.fetchedAt < $1.1.fetchedAt }
            return .stripe(snapshot: latest?.1, localName: row.name, metric: latest?.0.stripeMetric ?? match.first?.stripeMetric ?? .mrr, error: nil)
        case .paddle:
            let match = items.filter { $0.paddleAccountID == row.identifier }
            let latest = match.compactMap { c in c.paddleSnapshot.map { (c, $0) } }.max { $0.1.updatedAt < $1.1.updatedAt }
            return .paddle(snapshot: latest?.1, localName: row.name, metric: latest?.0.paddleMetric ?? match.first?.paddleMetric ?? .mrr, error: nil)
        case .shopify:
            let snapshot = items.filter { $0.shopifyStoreID == row.identifier }.compactMap(\.shopifySnapshot).max { $0.fetchedAt < $1.fetchedAt }
            return .shopify(snapshot: snapshot, localName: row.name, error: nil)
        }
    }

    var body: some View {
        // The directories and every Dock are read once per render, not once per row or check.
        let connections = rows
        let configurations = widgetConfigurations()
        GroupedSection("Connections", footer: "Credentials stay in this Mac’s Keychain.") {
            ForEach(connections) { row in
                GroupedRow(row.name.isEmpty ? row.kind.title : row.name,
                           subtitle: row.kind.title + " · Credentials saved",
                           symbol: row.kind.symbol, color: .gray) {
                    VStack(alignment: .trailing, spacing: 3) {
                        DataSourceProvenanceView(provenance: provenance(for: row, items: configurations), compact: true)
                    Menu("Manage") {
                        Button("Test Connection") { Task { await test(row) } }
                        Button("Replace Credentials…") {
                            provider = row.kind; name = row.name; replacingID = row.identifier; secret = ""; connectionFormExpanded = true
                            domain = ShopifyConnectionDirectory.stores().first(where: { $0.id == row.identifier })?.domain ?? ""
                        }
                        Menu("Assign to Widget") {
                            ForEach(store.customProfiles) { profile in
                                ForEach(profile.items.filter { $0.widgetKind == row.kind.rawValue }) { item in
                                    Button("\(profile.name) → \(item.displayName)") { assign(row, item: item, profileID: profile.id) }
                                }
                            }
                        }
                        Divider()
                        Button("Disconnect…", role: .destructive) { pendingDisconnect = row }
                    }.fixedSize().disabled(busy)
                    }
                }
            }
            if connections.isEmpty {
                GroupedRow("No business accounts connected", symbol: "link")
            }
            SettingsExpansionRow(title: replacingID == nil ? "Connect a service" : "Replace connection credentials", isExpanded: $connectionFormExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Picker("Service", selection: $provider) {
                ForEach(ConnectionKind.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(replacingID != nil || busy)
            TextField("Display name", text: $name).textFieldStyle(DockTextFieldStyle()).disabled(busy)
            if provider == .shopify {
                TextField("Store domain (name.myshopify.com)", text: $domain).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                TextField("Client ID", text: $clientID).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                SecureField("Client secret", text: $secret).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                Text("Shopify: read_orders only. Install the app on this store and use its client credentials. The available periods stay within the recent order history.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                SecureField(provider == .stripe ? "Restricted rk_ key" : "Paddle Billing API key", text: $secret).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                Text(provider == .stripe ? "Stripe: read-only Account, Balance, Balance Transactions, and Subscriptions." : PaddleAPIKeyStore.permissionSetupCopy)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(replacingID == nil ? "Test and Connect" : "Test and Replace") { Task { await connect() } }
                    .buttonStyle(DockButtonStyle(primary: true)).disabled(busy || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if replacingID != nil { Button("Cancel Replacement") { clearForm() }.disabled(busy) }
                if busy { ProgressView().controlSize(.small) }
            }
            }
            }
            if let message { GroupedRow(message).textSelection(.enabled) }
        }
        .id("Connections")
        .help("Manage business accounts here, then assign them to widgets. Credentials are excluded from profiles and backups.")
        // A typed secret does not outlive the form that holds it.
        .onChange(of: connectionFormExpanded) { expanded in if !expanded { secret = "" } }
        .onDisappear { secret = "" }
        .confirmationDialog("Disconnect this account?", isPresented: Binding(get: { pendingDisconnect != nil }, set: { if !$0 { pendingDisconnect = nil } })) {
            Button("Disconnect and Remove Credentials", role: .destructive) { disconnect() }
        } message: { Text("Every widget using this connection will be disconnected. This does not revoke access at the provider.") }
    }

    private func connect() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let key = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = provider, displayName = name, replacement = replacingID
        let storeDomain = domain, applicationID = clientID
        var clearSnapshotsFor: WidgetConnectionReference?
        do {
            let originalAuthority = try authority(service: service, id: replacement)
            switch service {
            case .stripe:
                let stripe = StripeAPIProvider()
                try await stripe.validate(apiKey: key)
                if let replacement, case .key(let oldKey)? = originalAuthority, oldKey != key {
                    let newIdentity = await stripe.accountIdentity(apiKey: key)
                    var oldIdentity: String?
                    if let oldKey { oldIdentity = await stripe.accountIdentity(apiKey: oldKey) }
                    if ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: oldIdentity, newIdentity: newIdentity, credentialsChanged: true) {
                        clearSnapshotsFor = .stripe(replacement)
                    }
                }
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                try StripeConnectionDirectory.save(StripeConnectedAccount(id: replacement ?? UUID().uuidString, name: displayName, color: "purple"), key: key)
            case .paddle:
                try await PaddleAPIProvider().validate(apiKey: key)
                // Paddle exposes no seller identity to this key scope, so a different key is treated as a possible tenant change.
                if let replacement, case .key(let oldKey)? = originalAuthority,
                   ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: nil, newIdentity: nil, credentialsChanged: oldKey != key) {
                    clearSnapshotsFor = .paddle(replacement)
                }
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                try PaddleConnectionDirectory.save(PaddleConnectedAccount(id: replacement ?? UUID().uuidString, name: displayName, color: "blue"), key: key)
            case .shopify:
                let connection = try await ShopifyAPIProvider().connect(domain: storeDomain, clientID: applicationID, clientSecret: key, color: "green")
                var account = connection.store
                if let replacement {
                    // Same store means the same normalized myshopify.com domain; the local connection ID and widget assignments stay.
                    guard let existing = ShopifyConnectionDirectory.stores().first(where: { $0.id == replacement }),
                          ShopifyAPIProvider.isSameStore(existing, connection.store) else {
                        throw ConnectionError.differentShopifyStore
                    }
                    account.id = replacement
                }
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { account.name = displayName }
                try ShopifyConnectionDirectory.save(account, credential: connection.credential)
            }
            clearForm(); revision += 1
            if let clearSnapshotsFor { store.clearPersistedSnapshots(for: clearSnapshotsFor) }
            store.widgetData.connectionsDidChange()
            message = clearSnapshotsFor == nil
                ? "Connection tested and saved. Assign it to a widget above."
                : "Connection saved. Saved figures from the previous account were cleared until the new account refreshes."
        } catch { message = error.localizedDescription }
    }

    private func test(_ row: ConnectionRow) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            switch row.kind {
            case .stripe:
                guard let key = try StripeAPIKeyStore.read(accountID: row.identifier) else { throw StripeDataError.missingKey }
                try await StripeAPIProvider().validate(apiKey: key)
            case .paddle:
                guard let key = try PaddleAPIKeyStore.read(accountID: row.identifier) else { throw PaddleDataError.missingKey }
                try await PaddleAPIProvider().validate(apiKey: key)
            case .shopify:
                guard let account = ShopifyConnectionDirectory.stores().first(where: { $0.id == row.identifier }),
                      let credential = try ShopifyCredentialStore.read(storeID: row.identifier) else { throw ShopifyDataError.invalidCredentials }
                let result = try await ShopifyAPIProvider().snapshot(store: account, credential: credential, period: .thirtyDays)
                try ShopifyCredentialStore.writeRefreshed(result.credential, replacing: credential, storeID: row.identifier)
            }
            message = "\(row.name): connection is available."
        } catch { message = error.localizedDescription }
    }

    private func disconnect() {
        guard let row = pendingDisconnect else { return }
        defer { pendingDisconnect = nil }
        do {
            switch row.kind {
            case .stripe: try StripeConnectionDirectory.remove(accountID: row.identifier)
            case .paddle: try PaddleConnectionDirectory.remove(accountID: row.identifier)
            case .shopify: try ShopifyConnectionDirectory.remove(storeID: row.identifier)
            }
            store.clearConnectionReferences(row.reference)
            store.widgetData.connectionsDidChange(); revision += 1
            message = "Connection removed."
        } catch { message = error.localizedDescription }
    }

    private func assign(_ row: ConnectionRow, item: DockItem, profileID: UUID) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { c in
            switch row.kind {
            case .stripe: c.stripeAccountID = row.identifier; c.stripeDisplayName = row.name; c.stripeSnapshot = nil
            case .paddle: c.paddleAccountID = row.identifier; c.paddleDisplayName = row.name; c.paddleSnapshot = nil
            case .shopify: c.shopifyStoreID = row.identifier; c.shopifyDisplayName = row.name; c.shopifySnapshot = nil
            }
        }
        store.widgetData.connectionsDidChange()
    }

    private func clearForm() { replacingID = nil; secret = ""; clientID = ""; domain = ""; name = "" }

    private enum Authority: Equatable {
        case key(String?)
        case shopify(String?, String?)
    }
    private func authority(service: ConnectionKind, id: String?) throws -> Authority? {
        guard let id else { return nil }
        switch service {
        case .stripe: return .key(try StripeAPIKeyStore.read(accountID: id))
        case .paddle: return .key(try PaddleAPIKeyStore.read(accountID: id))
        case .shopify:
            let c = try ShopifyCredentialStore.read(storeID: id)
            return .shopify(c?.clientID, c?.clientSecret)
        }
    }
    private func validateReplacement(service: ConnectionKind, id: String?, original: Authority?) throws {
        try Task.checkCancellation()
        guard let id else { return }
        guard rows.contains(where: { $0.kind == service && $0.identifier == id }),
              try authority(service: service, id: id) == original else {
            throw ConnectionError.changedWhileTesting
        }
    }
}
