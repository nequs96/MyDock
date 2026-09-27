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
    private var instanceLock: SingleInstanceLock?
    private var abortingDuplicateLaunch = false
    #if DEBUG
    private let visualPreview = ProcessInfo.processInfo.environment["MYDOCK_VISUAL_PREVIEW"] == "1"
        || (Bundle.main.bundleIdentifier?.hasPrefix(Product.bundleIdentifier) == true
            && Bundle.main.bundleIdentifier?.hasSuffix("VisualPreview") == true)
    private let countdownVisualPreview = Bundle.main.bundleIdentifier == Product.bundleIdentifier + "CountdownVisualPreview"
    private lazy var previewStore = ProfileStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("MyDock-VisualPreview-\(ProcessInfo.processInfo.processIdentifier).json"))
    private var store: ProfileStore { visualPreview ? previewStore : ProfileStore.shared }
    #else
    private lazy var store = ProfileStore.shared
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if visualPreview {
            if ProcessInfo.processInfo.environment["MYDOCK_VISUAL_DARK"] == "1" {
                NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            }
            store.updateSettings { $0.showRunningApps = false }
            let id = store.createProfile(kind: .custom, name: "Everyday")
            store.add(.widget("Clock"), to: id)
            store.add(.widget("Weather"), to: id)
            store.add(.widget("Focus Timer"), to: id)
            store.add(.widget("Sticky Note"), to: id)
            if countdownVisualPreview {
                var countdown = DockItem.widget("Countdown")
                countdown.widgetConfiguration?.setCountdownTarget(Date.now.addingTimeInterval(90_061))
                store.add(countdown, to: id)
            }
            NSApplication.shared.setActivationPolicy(.regular)
            showManager(nil)
            openSettings(nil)
            showWindow(id: "visual-preview", title: "Custom Dock Preview",
                       root: VisualDockPreviewSurface(store: store, profileID: id),
                       size: NSSize(width: countdownVisualPreview ? 960 : 620,
                                    height: countdownVisualPreview ? 560 : 420))
            return
        }
        #endif
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Product.bundleIdentifier)
            .first(where: { $0.processIdentifier < currentPID }) {
            abortingDuplicateLaunch = true
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
            return
        }
        do {
            instanceLock = try SingleInstanceLock()
        } catch SingleInstanceLockError.alreadyRunning {
            abortingDuplicateLaunch = true
            NSApplication.shared.terminate(nil)
            return
        } catch {
            abortingDuplicateLaunch = true
            let alert = NSAlert()
            alert.messageText = "MyDock could not start safely"
            alert.informativeText = "MyDock could not secure its profile store for exclusive use. Close other copies or check access to Application Support, then try again."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(store.state.settings.onboardingComplete ? .accessory : .regular)
        dockController = CustomDockWindowController(store: store)
        dockController?.update(state: store.state)
        installMenuBarItem()
        stateObservation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.dockController?.update(state: state)
            self?.rebuildMenu()
            NativeDockAutoSaveMonitor.shared.configure(
                enabled: state.settings.onboardingComplete && state.settings.automaticallySaveNativeDockChanges,
                profileID: state.settings.activeNativeProfileID)
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
        if abortingDuplicateLaunch { return .terminateNow }
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
        item.button?.imagePosition = .imageLeading
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let title = store.state.settings.showActiveProfileNameInMenuBar
            ? MenuBarProfileTitle.title(in: store.state) : nil
        statusItem.length = title == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
        statusItem.button?.title = title ?? ""
        let description = MenuBarProfileTitle.toolTip(in: store.state)
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
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
        showWindow(id: "settings", title: "Settings", root: SettingsView(store: store), size: NSSize(width: 860, height: 700))
    }
    func showSettingsFromAppMenu() { openSettings(nil) }
    func showManagerFromAppMenu() { showManager(nil) }
    @objc private func openAbout(_ sender: Any?) {
        showWindow(id: "about", title: "About \(Product.name)", root: AboutView(onReplaySetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 420, height: 360))
    }
    @objc private func quit(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    private func showManager(_ sender: Any?) {
        showWindow(id: "manager", title: "Manage Docks", root: DockManagerView(store: store, onContinueSetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 1060, height: 650))
    }

    private func showOnboarding() {
        showWindow(id: "onboarding", title: "Set up MyDock", root: OnboardingView(store: store) { [weak self] in
            self?.windows["onboarding"]?.close()
            self?.showManager(nil)
        }, size: NSSize(width: 760, height: 600))
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

#if DEBUG
private struct VisualDockPreviewSurface: View {
    @ObservedObject var store: ProfileStore
    let profileID: UUID

    var body: some View {
        if let profile = store.state.profiles.first(where: { $0.id == profileID }) {
            let settings = store.state.settings
            let scale = CGFloat(settings.customDockSize)
            let length = DockSurfaceMetrics.contentLength(items: profile.items, settings: settings, scale: scale)
            let horizontal = settings.customDockPosition == .bottom
            ZStack {
                LinearGradient(colors: [DockDesign.accent.opacity(0.16), DockDesign.page],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                CustomDockView(store: store, profile: profile)
                    .frame(width: horizontal ? min(length, 560) : 76 * scale,
                           height: horizontal ? 76 * scale : min(length, 360))
            }
        }
    }
}
#endif
