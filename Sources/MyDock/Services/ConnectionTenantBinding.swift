import Foundation

/// Decides whether persisted widget readings may stay after a connection's credentials are replaced.
/// Provider identity (for example a Stripe account ID) is compared when both sides are known.
enum ConnectionTenantPolicy {
    /// - Parameters:
    ///   - oldIdentity: Provider tenant of the previous credentials, nil when it could not be determined.
    ///   - newIdentity: Provider tenant of the replacement credentials, nil when unavailable.
    ///   - credentialsChanged: Whether the replacement differs from the stored credentials.
    static func shouldClearSnapshots(oldIdentity: String?, newIdentity: String?, credentialsChanged: Bool) -> Bool {
        guard credentialsChanged else { return false }
        if let oldIdentity, let newIdentity, !oldIdentity.isEmpty, !newIdentity.isEmpty {
            return oldIdentity != newIdentity
        }
        // An unknown identity with a different key cannot be proven to be the same tenant.
        return true
    }
}

extension ProfileStore {
    /// Explicit save/disconnect invalidates the previous Copilot authority, including in-flight requests.
    func invalidateCopilotLimitReadings() {
        widgetData.connectionsDidChange()
        for profile in state.profiles {
            for item in profile.items where item.widgetKind == "AI Limits" {
                updateWidgetConfiguration(itemID: item.id, in: profile.id) { configuration in
                    configuration.aiLimitsSnapshot?.readings.removeAll { $0.provider == .copilot }
                }
            }
        }
    }

    /// Removes persisted figures for one connection while keeping the widget assigned to it.
    /// Returns how many widgets were cleared.
    @discardableResult
    func clearPersistedSnapshots(for connection: WidgetConnectionReference) -> Int {
        guard !connection.identifier.isEmpty else { return 0 }
        var cleared = 0
        for profile in state.profiles {
            for item in profile.items where item.type == .widget {
                guard let configuration = presentationItem(item).widgetConfiguration else { continue }
                let matches: Bool
                switch connection {
                case .stripe(let id): matches = item.widgetKind == "Stripe" && configuration.stripeAccountID == id && configuration.stripeSnapshot != nil
                case .paddle(let id): matches = item.widgetKind == "Paddle" && configuration.paddleAccountID == id && configuration.paddleSnapshot != nil
                case .shopify(let id): matches = item.widgetKind == "Shopify" && configuration.shopifyStoreID == id && configuration.shopifySnapshot != nil
                }
                guard matches else { continue }
                updateWidgetConfiguration(itemID: item.id, in: profile.id) { c in
                    switch connection {
                    case .stripe: c.stripeSnapshot = nil
                    case .paddle: c.paddleSnapshot = nil
                    case .shopify: c.shopifySnapshot = nil
                    }
                }
                cleared += 1
            }
        }
        return cleared
    }
}
