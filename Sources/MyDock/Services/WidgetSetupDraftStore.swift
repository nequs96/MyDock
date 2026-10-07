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

    func noteDraft(for itemID: UUID, in profileID: UUID) -> String? {
        guard let draft = noteDrafts[itemID], draft.profileID == profileID else { return nil }
        return draft.text
    }

    /// Retain the current input until the candidate has actually reached durable storage.
    func saveNote(_ text: String, for itemID: UUID, in profileID: UUID, to store: ProfileStore) throws {
        // An obsolete debounce completion must not overwrite a newer pending edit.
        if let draft = noteDrafts[itemID], draft.profileID != profileID || draft.text != text { return }
        // Opening and closing an unchanged note writes nothing: the saved text already matches.
        if !store.hasUnpersistedChanges,
           store.state.profiles.first(where: { $0.id == profileID })?.items.first(where: { $0.id == itemID })?.widgetConfiguration?.noteText == text {
            noteWasSaved(text, for: itemID)
            return
        }
        updateNoteDraft(text, for: itemID, in: profileID)
        try store.updateWidgetConfigurationAndPersist(itemID: itemID, in: profileID) { $0.noteText = text }
        noteWasSaved(text, for: itemID)
    }

    private func noteWasSaved(_ text: String, for itemID: UUID) {
        if noteDrafts[itemID]?.text == text { noteDrafts.removeValue(forKey: itemID) }
    }

    @discardableResult
    func flushNotes(to store: ProfileStore) -> Result<Void, Error> {
        // A draft whose widget no longer exists can never be saved; it must not fail the batch or block quit forever.
        for (itemID, draft) in noteDrafts where !store.hasWidget(itemID: itemID, in: draft.profileID) {
            noteDrafts.removeValue(forKey: itemID)
        }
        let pending = noteDrafts
        do {
            try store.persistNoteDrafts(pending.map { (itemID: $0.key, profileID: $0.value.profileID, text: $0.value.text) })
            for (itemID, draft) in pending { noteWasSaved(draft.text, for: itemID) }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func clearDrafts(for itemID: UUID) {
        stripeDrafts.removeValue(forKey: itemID)
        paddleDrafts.removeValue(forKey: itemID)
        shopifyDrafts.removeValue(forKey: itemID)
        weatherDrafts.removeValue(forKey: itemID)
        noteDrafts.removeValue(forKey: itemID)
    }
}
