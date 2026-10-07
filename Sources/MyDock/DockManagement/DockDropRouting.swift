import Foundation

/// What a drop on the live Dock does. The router decides; the Dock view applies it to the store.
enum DockDropAction: Equatable {
    /// The drop is refused.
    case rejected
    /// Pin running or recent apps before `before` (nil: at the end of the pinned items). Each pinned
    /// copy gets a fresh identity when it is saved.
    case pin([DockItem], before: UUID?)
    /// Reorder this Dock's own items before `before` (nil: at the end of the pinned items).
    case move(Set<UUID>, before: UUID?)
    /// Remove pinned apps (dropped on the running-apps boundary).
    case unpin(Set<UUID>)
}

/// Pure drop routing for the live Dock, so the routing table can be tested without a view.
enum DockDropRouter {
    /// A Dock drag payload dropped before `targetID`, or on the running-apps boundary when `unpin`.
    /// `runtimeApps` are the unpinned running and recent apps the Dock shows.
    static func typedDrop(_ payload: DockDragPayload, profile: DockProfile, runtimeApps: [DockItem],
                          before targetID: UUID?, unpin: Bool) -> DockDropAction {
        if let bundleID = payload.runningBundleIdentifier {
            // Compatibility with older drag producers: only an unambiguous
            // installed copy may be pinned by a bundle-only payload.
            let matches = runtimeApps.filter { $0.bundleIdentifier == bundleID }
            guard !unpin, matches.count == 1 else { return .rejected }
            return .pin(matches, before: targetID)
        }
        guard payload.profileID == profile.id, !payload.itemIDs.isEmpty else { return .rejected }
        let running = runtimeApps.filter { payload.itemIDs.contains($0.id) }
        if !running.isEmpty {
            guard !unpin, running.count == payload.itemIDs.count else { return .rejected }
            return .pin(running, before: targetID)
        }
        if unpin {
            let apps = profile.items.filter { payload.itemIDs.contains($0.id) && $0.type == .application }
            return apps.isEmpty ? .rejected : .unpin(Set(apps.map(\.id)))
        }
        return .move(Set(payload.itemIDs), before: targetID)
    }

    /// Finder files and web addresses dropped at the end of the pinned items: at most
    /// `DockDropOpenPolicy.maximumURLs`, existing files only, and web links through `DockLinkPolicy`
    /// (http or https, never credentials in the address).
    static func externalItems(for urls: [URL], fileExists: (URL) -> Bool, isDirectory: (URL) -> Bool) -> [DockItem] {
        urls.prefix(DockDropOpenPolicy.maximumURLs).compactMap { url -> DockItem? in
            if url.isFileURL {
                guard fileExists(url) else { return nil }
                return url.pathExtension.lowercased() == "app" ? .application(at: url) : .file(at: url, isFolder: isDirectory(url))
            }
            guard let link = DockLinkPolicy.validatedURL(url.absoluteString) else { return nil }
            return .link(link, title: link.host ?? link.absoluteString)
        }
    }
}
