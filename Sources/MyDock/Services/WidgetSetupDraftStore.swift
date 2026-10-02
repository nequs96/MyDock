import Combine
import Foundation

struct StripeConnectionDraft: Equatable {
    var accountName = ""
    var restrictedKey = ""
    var color = DockProfileColor.purple.rawValue

    var isPristine: Bool { accountName.isEmpty && restrictedKey.isEmpty && color == DockProfileColor.purple.rawValue }
}

struct PaddleConnectionDraft: Equatable {
    var accountName = ""
    var apiKey = ""
    var color = DockProfileColor.blue.rawValue

    var isPristine: Bool { accountName.isEmpty && apiKey.isEmpty && color == DockProfileColor.blue.rawValue }
}

struct ShopifyConnectionDraft: Equatable {
    var accountName = ""
    var domain = ""
    var clientID = ""
    var clientSecret = ""
    var color = DockProfileColor.green.rawValue

    var isPristine: Bool {
        accountName.isEmpty && domain.isEmpty && clientID.isEmpty && clientSecret.isEmpty
            && color == DockProfileColor.green.rawValue
    }
}

struct WeatherLocationDraft: Equatable {
    var searchText = ""
    var isChangingLocation = false
    var searchResults: [WeatherLocation] = []

    var isPristine: Bool { searchText.isEmpty && !isChangingLocation && searchResults.isEmpty }
}

/// Holds unfinished widget forms for this process only. Credentials in these drafts are never encoded.
@MainActor
final class WidgetSetupDraftStore: ObservableObject {
    static let shared = WidgetSetupDraftStore()

    @Published private var stripeDrafts: [UUID: StripeConnectionDraft] = [:]
    @Published private var paddleDrafts: [UUID: PaddleConnectionDraft] = [:]
    @Published private var shopifyDrafts: [UUID: ShopifyConnectionDraft] = [:]
    @Published private var weatherDrafts: [UUID: WeatherLocationDraft] = [:]
    private var noteDrafts: [UUID: (profileID: UUID, text: String)] = [:]

    var hasPendingNotes: Bool { !noteDrafts.isEmpty }

    func stripeDraft(for itemID: UUID) -> StripeConnectionDraft { stripeDrafts[itemID] ?? StripeConnectionDraft() }
    func paddleDraft(for itemID: UUID) -> PaddleConnectionDraft { paddleDrafts[itemID] ?? PaddleConnectionDraft() }
    func shopifyDraft(for itemID: UUID) -> ShopifyConnectionDraft { shopifyDrafts[itemID] ?? ShopifyConnectionDraft() }
    func weatherDraft(for itemID: UUID) -> WeatherLocationDraft { weatherDrafts[itemID] ?? WeatherLocationDraft() }

    func updateStripeDraft(for itemID: UUID, _ update: (inout StripeConnectionDraft) -> Void) {
        var draft = stripeDraft(for: itemID)
        update(&draft)
        if draft.isPristine { stripeDrafts.removeValue(forKey: itemID) }
        else { stripeDrafts[itemID] = draft }
    }

    func updatePaddleDraft(for itemID: UUID, _ update: (inout PaddleConnectionDraft) -> Void) {
        var draft = paddleDraft(for: itemID)
        update(&draft)
        if draft.isPristine { paddleDrafts.removeValue(forKey: itemID) }
        else { paddleDrafts[itemID] = draft }
    }

    func updateShopifyDraft(for itemID: UUID, _ update: (inout ShopifyConnectionDraft) -> Void) {
        var draft = shopifyDraft(for: itemID)
        update(&draft)
        if draft.isPristine { shopifyDrafts.removeValue(forKey: itemID) }
        else { shopifyDrafts[itemID] = draft }
    }

    func updateWeatherDraft(for itemID: UUID, _ update: (inout WeatherLocationDraft) -> Void) {
        var draft = weatherDraft(for: itemID)
        update(&draft)
        if draft.isPristine { weatherDrafts.removeValue(forKey: itemID) }
        else { weatherDrafts[itemID] = draft }
    }

    func updateNoteDraft(_ text: String, for itemID: UUID, in profileID: UUID) {
        noteDrafts[itemID] = (profileID, text)
    }

    func noteWasSaved(_ text: String, for itemID: UUID) {
        if noteDrafts[itemID]?.text == text { noteDrafts.removeValue(forKey: itemID) }
    }

    func flushNotes(to store: ProfileStore) {
        let pending = noteDrafts
        noteDrafts.removeAll()
        for (itemID, draft) in pending {
            store.updateWidgetConfiguration(itemID: itemID, in: draft.profileID) { $0.noteText = draft.text }
        }
        if !pending.isEmpty { store.flush() }
    }

    func clearDrafts(for itemID: UUID) {
        stripeDrafts.removeValue(forKey: itemID)
        paddleDrafts.removeValue(forKey: itemID)
        shopifyDrafts.removeValue(forKey: itemID)
        weatherDrafts.removeValue(forKey: itemID)
        noteDrafts.removeValue(forKey: itemID)
    }
}
