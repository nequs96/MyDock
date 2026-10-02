import SwiftUI

struct ConnectionsCenterView: View {
    @ObservedObject var store: ProfileStore
    @State private var provider = "Stripe"
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
        var kind: String
        var identifier: String
        var name: String
        var id: String { kind + identifier }
        var reference: WidgetConnectionReference {
            switch kind { case "Stripe": .stripe(identifier); case "Paddle": .paddle(identifier); default: .shopify(identifier) }
        }
    }

    private var rows: [ConnectionRow] {
        _ = revision
        return StripeConnectionDirectory.accounts().map { ConnectionRow(kind: "Stripe", identifier: $0.id, name: $0.name) }
            + PaddleConnectionDirectory.accounts().map { ConnectionRow(kind: "Paddle", identifier: $0.id, name: $0.name) }
            + ShopifyConnectionDirectory.stores().map { ConnectionRow(kind: "Shopify", identifier: $0.id, name: $0.name) }
    }

    var body: some View {
        DockSettingSection(title: "Connections") {
            Text("Manage business accounts here, then assign them to widgets. Credentials stay in this Mac’s Keychain and are excluded from profiles and backups.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.kind == "Shopify" ? "bag" : "creditcard")
                        .font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name.isEmpty ? row.kind : row.name).font(.system(size: 13, weight: .medium))
                        Text(row.kind + " · Connected").font(DockDesign.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Manage") {
                        Button("Test Connection") { Task { await test(row) } }
                        Button("Replace Credentials…") {
                            provider = row.kind; name = row.name; replacingID = row.identifier; secret = ""; connectionFormExpanded = true
                            domain = ShopifyConnectionDirectory.stores().first(where: { $0.id == row.identifier })?.domain ?? ""
                        }
                        Menu("Assign to widget") {
                            ForEach(store.customProfiles) { profile in
                                ForEach(profile.items.filter { $0.widgetKind == row.kind }) { item in
                                    Button("\(profile.name) → \(item.displayName)") { assign(row, item: item, profileID: profile.id) }
                                }
                            }
                        }
                        Divider()
                        Button("Disconnect…", role: .destructive) { pendingDisconnect = row }
                    }.fixedSize().disabled(busy)
                }.frame(minHeight: 44)
            }
            if rows.isEmpty {
                Label("No business accounts connected", systemImage: "link")
                    .font(DockDesign.body).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            Divider()
            DisclosureGroup(replacingID == nil ? "Connect a service" : "Replace connection credentials", isExpanded: $connectionFormExpanded) {
            VStack(alignment: .leading, spacing: 12) {
            Picker("Service", selection: $provider) {
                ForEach(["Stripe", "Paddle", "Shopify"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).disabled(replacingID != nil || busy)
            TextField("Display name", text: $name).textFieldStyle(DockTextFieldStyle()).disabled(busy)
            if provider == "Shopify" {
                TextField("Store domain (name.myshopify.com)", text: $domain).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                TextField("Client ID", text: $clientID).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                SecureField("Client secret", text: $secret).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                Text("Shopify: read_orders only. Install the app on this store and use its client credentials. The available periods stay within the recent order history.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                SecureField(provider == "Stripe" ? "Restricted rk_ key" : "Paddle Billing API key", text: $secret).textFieldStyle(DockTextFieldStyle()).disabled(busy)
                Text(provider == "Stripe" ? "Stripe: read-only Account, Balance, Balance Transactions, and Subscriptions." : "Paddle Billing: read-only transactions and subscriptions. Both live and sandbox keys are supported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(replacingID == nil ? "Test and Connect" : "Test and Replace") { Task { await connect() } }
                    .buttonStyle(DockButtonStyle(primary: true)).disabled(busy || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if replacingID != nil { Button("Cancel Replacement") { clearForm() }.disabled(busy) }
                if busy { ProgressView().controlSize(.small) }
            }
            }.padding(.top, 12)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
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
        do {
            let originalAuthority = try authority(service: service, id: replacement)
            switch service {
            case "Stripe":
                try await StripeAPIProvider().validate(apiKey: key)
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                try StripeConnectionDirectory.save(StripeConnectedAccount(id: replacement ?? UUID().uuidString, name: displayName, color: "purple"), key: key)
            case "Paddle":
                try await PaddleAPIProvider().validate(apiKey: key)
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                try PaddleConnectionDirectory.save(PaddleConnectedAccount(id: replacement ?? UUID().uuidString, name: displayName, color: "blue"), key: key)
            default:
                let connection = try await ShopifyAPIProvider().connect(domain: storeDomain, clientID: applicationID, clientSecret: key, color: "green")
                if let replacement, replacement != connection.store.id { throw EditSessionSaveError.failed("This is a different Shopify store. Cancel replacement and add it as a separate connection.") }
                try validateReplacement(service: service, id: replacement, original: originalAuthority)
                var account = connection.store
                if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { account.name = displayName }
                try ShopifyConnectionDirectory.save(account, credential: connection.credential)
            }
            clearForm(); revision += 1
            store.widgetData.connectionsDidChange()
            message = "Connection tested and saved. Assign it to a widget above."
        } catch { message = error.localizedDescription }
    }

    private func test(_ row: ConnectionRow) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            switch row.kind {
            case "Stripe":
                guard let key = try StripeAPIKeyStore.read(accountID: row.identifier) else { throw StripeDataError.missingKey }
                try await StripeAPIProvider().validate(apiKey: key)
            case "Paddle":
                guard let key = try PaddleAPIKeyStore.read(accountID: row.identifier) else { throw PaddleDataError.missingKey }
                try await PaddleAPIProvider().validate(apiKey: key)
            default:
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
            case "Stripe": try StripeConnectionDirectory.remove(accountID: row.identifier)
            case "Paddle": try PaddleConnectionDirectory.remove(accountID: row.identifier)
            default: try ShopifyConnectionDirectory.remove(storeID: row.identifier)
            }
            store.clearConnectionReferences(row.reference)
            store.widgetData.connectionsDidChange(); revision += 1
            message = "Connection removed."
        } catch { message = error.localizedDescription }
    }

    private func assign(_ row: ConnectionRow, item: DockItem, profileID: UUID) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { c in
            switch row.kind {
            case "Stripe": c.stripeAccountID = row.identifier; c.stripeDisplayName = row.name; c.stripeSnapshot = nil
            case "Paddle": c.paddleAccountID = row.identifier; c.paddleDisplayName = row.name; c.paddleSnapshot = nil
            default: c.shopifyStoreID = row.identifier; c.shopifyDisplayName = row.name; c.shopifySnapshot = nil
            }
        }
        store.widgetData.connectionsDidChange()
    }

    private func clearForm() { replacingID = nil; secret = ""; clientID = ""; domain = ""; name = "" }

    private enum Authority: Equatable {
        case key(String?)
        case shopify(String?, String?)
    }
    private func authority(service: String, id: String?) throws -> Authority? {
        guard let id else { return nil }
        switch service {
        case "Stripe": return .key(try StripeAPIKeyStore.read(accountID: id))
        case "Paddle": return .key(try PaddleAPIKeyStore.read(accountID: id))
        default:
            let c = try ShopifyCredentialStore.read(storeID: id)
            return .shopify(c?.clientID, c?.clientSecret)
        }
    }
    private func validateReplacement(service: String, id: String?, original: Authority?) throws {
        try Task.checkCancellation()
        guard let id else { return }
        guard rows.contains(where: { $0.kind == service && $0.identifier == id }),
              try authority(service: service, id: id) == original else {
            throw EditSessionSaveError.failed("This connection changed or was removed while testing. Its credentials were left untouched.")
        }
    }
}
