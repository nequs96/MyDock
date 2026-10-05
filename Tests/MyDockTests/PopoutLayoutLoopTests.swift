import AppKit
import SwiftUI
import Testing
@testable import MyDock

/// FX-01: the Trash popout (and, latently, every popout) put AppKit into an endless
/// "Update Constraints in Window" loop when its NSHostingView sized the window.
///
/// Family content is vertically compressible (`WidgetPopoutHero` scales its value to fit),
/// so the hosting view published a window content min height below the max height. Each
/// constraints pass then re-measured the content at the current height, got back a
/// fractional height a little smaller, rounded it down and shrank the window one point,
/// until AppKit raised NSGenericException ("…more Update Constraints in Window passes than
/// there are views in the window"). The shell now sizes to its content's ideal height.
@MainActor
struct PopoutLayoutLoopTests {
    /// The real error string shapes the live popover can show: the isolated-session
    /// message, a typical permission error and a long one that wraps several lines.
    static let trashMessages = [
        TrashStatus.isolatedMessage,
        "The file “.Trash” couldn’t be opened because you don’t have permission to view it.",
        String(repeating: "MyDock could not read the contents of your home Trash because macOS denied access. ", count: 4),
    ]
    /// The size the DEBUG widget export renders each popout at (it crashed here).
    static let exportSize = NSSize(width: 460, height: 680)

    private func store() throws -> (ProfileStore, UUID, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Popout layout")
        return (store, id, directory)
    }

    private func item(_ kind: String, in store: ProfileStore, profile id: UUID) -> DockItem {
        let fresh = DockItem.widget(kind)
        store.add(fresh, to: id)
        return store.state.profiles.first { $0.id == id }?.items.first { $0.id == fresh.id } ?? fresh
    }

    /// Hosts the popout exactly as the widget export does: the hosting view is the
    /// window's content view, so it drives the window's content min/max size.
    private func hostInWindow(_ view: some View, size: NSSize) -> (NSWindow, NSHostingView<AnyView>) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AnyView(view
            .font(DockDesign.body).buttonStyle(DockButtonStyle()).tint(DockDesign.accent)
            .environment(\.colorScheme, .dark).environment(\.dockSnapshotRendering, true)))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        return (window, host)
    }

    /// Forces several constraint and layout passes, letting SwiftUI's deferred updates land between them.
    private func settle(_ window: NSWindow, _ host: NSView) async throws {
        for _ in 0..<4 {
            window.updateConstraintsIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        window.updateConstraintsIfNeeded()
        host.layoutSubtreeIfNeeded()
    }

    /// The popout's height must not depend on the height it is offered: a squeezable shell is
    /// what let the window's min and max content heights differ and the window ratchet down.
    private func expectRigid(_ view: AnyView, _ label: String) {
        let measure = NSHostingController(rootView: view)
        let width = Self.exportSize.width
        let squeezed = measure.sizeThatFits(in: CGSize(width: width, height: 1)).height
        let roomy = measure.sizeThatFits(in: CGSize(width: width, height: 20_000)).height
        #expect(abs(squeezed - roomy) < 0.5, "\(label): popout height \(squeezed) when squeezed vs \(roomy) with room")
    }

    @Test func trashPopoutSettlesInAWindowWithEveryErrorShape() async throws {
        let (store, id, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trash = item("Trash", in: store, profile: id)
        defer { TrashQAFixture.override = nil }
        for message in Self.trashMessages + [nil] {
            TrashQAFixture.override = (count: message == nil ? 3 : 0, errorMessage: message)
            let popout = AnyView(WidgetPopout(store: store, item: trash, profileID: id).padding(20).background(WidgetDesign.surface))
            let (window, host) = hostInWindow(popout, size: Self.exportSize)
            defer { window.close() }
            // Before the fix AppKit raised NSGenericException from these passes and aborted the process.
            try await settle(window, host)
            let label = "Trash (\(message ?? "3 items"))"
            #expect(window.contentMinSize.height == window.contentMaxSize.height,
                    "\(label): window content height range \(window.contentMinSize.height)…\(window.contentMaxSize.height)")
            #expect(abs(host.frame.height - host.fittingSize.height) <= 1, "\(label): window \(host.frame.height) vs content \(host.fittingSize.height)")
            expectRigid(popout, label)
        }
    }

    /// The cause sat in the shared shell, so every family's popout must be rigid too.
    /// (Unit Converter hit the same loop once Trash no longer stopped the export.)
    @Test func everyFamilyPopoutIsVerticallyRigid() async throws {
        let (store, id, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        for definition in WidgetRegistry.all {
            let shown = item(definition.name, in: store, profile: id)
            let popout = AnyView(WidgetPopout(store: store, item: shown, profileID: id).padding(20).background(WidgetDesign.surface))
            let (window, host) = hostInWindow(popout, size: Self.exportSize)
            defer { window.close() }
            try await settle(window, host)
            #expect(window.contentMinSize.height == window.contentMaxSize.height,
                    "\(definition.name): window content height range \(window.contentMinSize.height)…\(window.contentMaxSize.height)")
            expectRigid(popout, definition.name)
        }
    }
}
