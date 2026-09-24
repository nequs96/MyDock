import AppKit
import Combine
import SwiftUI

@main
struct MyDockApp: App {
    @NSApplicationDelegateAdaptor(MyDockAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.showSettingsFromAppMenu() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .appSettings) {
                    Button("Manage Docks…") { appDelegate.showManagerFromAppMenu() }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }
    }
}

@MainActor
final class MyDockAppDelegate: NSObject, NSApplicationDelegate {
    private var dockController: CustomDockWindowController?
    private var statusItem: NSStatusItem?
    private var stateObservation: AnyCancellable?
    private var shortcutObservation: AnyCancellable?
    private var windows: [String: NSWindow] = [:]
    private var pendingCustomMainMode: Bool?
    private var customMainModeTask: Task<Void, Never>?
    private let store = ProfileStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(store.state.settings.onboardingComplete ? .accessory : .regular)
        dockController = CustomDockWindowController(store: store)
        dockController?.update(state: store.state)
        installMenuBarItem()
        stateObservation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.dockController?.update(state: state)
            self?.rebuildMenu()
            NSApplication.shared.setActivationPolicy(state.settings.onboardingComplete ? .accessory : .regular)
            let activeCustomProfileExists = state.settings.activeCustomProfileID.map { id in
                state.profiles.contains { $0.id == id && $0.kind == .custom }
            } ?? false
            self?.synchronizeCustomMainMode(state.settings.setupMode == .customMain && activeCustomProfileExists)
        }
        GlobalShortcutController.shared.onActivateProfile = { [weak self] profileID in
            self?.activateProfile(profileID)
        }
        shortcutObservation = DockShortcutStore.shared.$bindings.receive(on: RunLoop.main).sink { bindings in
            GlobalShortcutController.shared.register(bindings)
        }
        if !store.state.settings.onboardingComplete {
            showOnboarding()
        }
        Task { @MainActor in
            do { try await NativeDockController.shared.recoverInterruptedTransaction() }
            catch { NSLog("MyDock could not recover an interrupted Dock operation: %@", error.localizedDescription) }
            await AlarmNotificationService.reconcileSchedules(in: store)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard NativeDockAutoHideController.shared.hasPendingRestore else { return .terminateNow }
        Task { @MainActor in
            do {
                try await NativeDockAutoHideController.shared.restoreBeforeExit()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Apple Dock settings could not be restored"
                alert.informativeText = "MyDock could not restore the Dock's previous auto-hide setting. The recovery record was kept; try quitting again after resolving the issue.\n\n\(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    private func synchronizeCustomMainMode(_ enabled: Bool) {
        pendingCustomMainMode = enabled
        guard customMainModeTask == nil else { return }
        customMainModeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let requested = pendingCustomMainMode {
                pendingCustomMainMode = nil
                do {
                    try await NativeDockAutoHideController.shared.setCustomDockMain(requested)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = requested ? "Could not hide the macOS Dock" : "Could not restore the macOS Dock"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
            customMainModeTask = nil
        }
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: Product.name)
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        if !store.nativeProfiles.isEmpty {
            let heading = NSMenuItem(title: "macOS Dock", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for profile in store.nativeProfiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.state = store.state.settings.activeNativeProfileID == profile.id ? .on : .off
                menu.addItem(item)
            }
        }
        if !store.customProfiles.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let heading = NSMenuItem(title: "Custom Dock", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for profile in store.customProfiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.state = store.state.settings.activeCustomProfileID == profile.id ? .on : .off
                menu.addItem(item)
            }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: "Manage Docks…", action: #selector(openManager(_:)), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "About \(Product.name)", action: #selector(openAbout(_:)), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(Product.name)", action: #selector(quit(_:)), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        activateProfile(id)
    }

    private func activateProfile(_ id: UUID) {
        guard let profile = store.state.profiles.first(where: { $0.id == id }) else { return }
        if profile.kind == .custom {
            store.activate(id)
        } else {
            Task { @MainActor in
                do {
                    try await NativeDockController.shared.apply(profile)
                    store.activate(id)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not switch the macOS Dock"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    @objc private func openManager(_ sender: Any?) { showManager(sender) }
    @objc private func openSettings(_ sender: Any?) {
        showWindow(id: "settings", title: "Settings", root: SettingsView(store: store), size: NSSize(width: 700, height: 620))
    }
    func showSettingsFromAppMenu() { openSettings(nil) }
    func showManagerFromAppMenu() { showManager(nil) }
    @objc private func openAbout(_ sender: Any?) {
        showWindow(id: "about", title: "About \(Product.name)", root: AboutView(onReplaySetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 380, height: 310))
    }
    @objc private func quit(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    private func showManager(_ sender: Any?) {
        showWindow(id: "manager", title: "Manage Docks", root: DockManagerView(store: store, onContinueSetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 960, height: 600))
    }

    private func showOnboarding() {
        showWindow(id: "onboarding", title: "Set up MyDock", root: OnboardingView(store: store) { [weak self] in
            self?.windows["onboarding"]?.close()
            self?.showManager(nil)
        }, size: NSSize(width: 680, height: 500))
    }

    private func showWindow<Content: View>(id: String, title: String, root: Content, size: NSSize) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.center()
            windows[id] = window
        }
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
