import AppKit
import Combine
import SwiftUI

@main
struct MyDockApp: App {
    @NSApplicationDelegateAdaptor(MyDockAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(Product.name)") { appDelegate.showAboutFromAppMenu() }
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.showSettingsFromAppMenu() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .appSettings) {
                    Button("Manage Docks…") { appDelegate.showManagerFromAppMenu() }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                CommandGroup(replacing: .help) {
                    Button("Keyboard Shortcuts") { appDelegate.showKeyboardShortcutsFromMenu() }
                    Button("What's New in \(Product.name)") { appDelegate.showWhatsNewFromMenu() }
                }
            }
    }
}

@MainActor
final class MyDockAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var dockController: CustomDockWindowController?
    private var statusItem: NSStatusItem?
    private var stateObservation: AnyCancellable?
    private var persistenceObservation: AnyCancellable?
    private var shortcutObservation: AnyCancellable?
    private var wakeReconcileObservation: AnyCancellable?
    private var automaticSwitching: AutomaticSwitchingController?
    private var automaticSwitchingObservation: AnyCancellable?
    private var windows: [String: NSWindow] = [:]
    private let workspaceNavigation = DockWorkspaceNavigation()
    private var pendingCustomMainMode: Bool?
    private var customMainModeTask: Task<Void, Never>?
    private var lastCustomMainModeAttempt: Bool?
    private var instanceLock: SingleInstanceLock?
    private var abortingDuplicateLaunch = false
    private var quitWithoutSaving = false
    #if DEBUG
    private let unitTestHost = ProcessInfo.processInfo.environment["MYDOCK_UNIT_TEST_HOST"] == "1"
    private let visualPreview = ProcessInfo.processInfo.environment["MYDOCK_VISUAL_PREVIEW"] == "1"
        || (Bundle.main.bundleIdentifier?.hasPrefix(Product.bundleIdentifier) == true
            && Bundle.main.bundleIdentifier?.hasSuffix("VisualPreview") == true)
    private let countdownVisualPreview = ProcessInfo.processInfo.environment["MYDOCK_COUNTDOWN_VISUAL_PREVIEW"] == "1"
        || Bundle.main.bundleIdentifier == Product.bundleIdentifier + "CountdownVisualPreview"
    private let previewDirectory = (AppRuntimeEnvironment.validationRoot ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("MyDock-VisualPreview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    private lazy var previewStore = ProfileStore(fileURL: previewDirectory.appendingPathComponent("state.json"), allowsSystemChanges: false)
    private var store: ProfileStore { AppRuntimeEnvironment.isIsolated ? previewStore : ProfileStore.shared }
    #else
    private lazy var store = ProfileStore.shared
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if unitTestHost { return }
        #endif
        NSApplication.shared.appearance = MyDockInterfaceAppearance.current.native
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["MYDOCK_RENDER_QA"] {
            Task { @MainActor in
                do {
                    try await PremiumVisualQA.export(to: URL(fileURLWithPath: directory, isDirectory: true), store: previewStore)
                    print("MyDock render matrix exported")
                } catch { print("MyDock render failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if visualPreview || AppRuntimeEnvironment.isIsolated {
            if let dark = ProcessInfo.processInfo.environment["MYDOCK_VISUAL_DARK"] {
                NSApplication.shared.appearance = NSAppearance(named: dark == "1" ? .darkAqua : .aqua)
            }
            let previewPosition = DockPosition(rawValue: ProcessInfo.processInfo.environment["MYDOCK_VISUAL_POSITION"] ?? "") ?? .bottom
            store.updateSettings {
                $0.showRunningApps = false
                $0.customDockPosition = previewPosition
                $0.customDockTheme = ProcessInfo.processInfo.environment["MYDOCK_VISUAL_DARK"] == "0" ? .light : .dark
            }
            guard let id = try? store.createProfileAndPersist(kind: .custom, name: "Everyday") else {
                NSApplication.shared.terminate(nil); return
            }
            let adaptivePreview = ProcessInfo.processInfo.environment["MYDOCK_ADAPTIVE_PREVIEW"] == "1"
            if adaptivePreview {
                for bundle in ["com.apple.finder", "com.apple.Safari"] {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
                }
                store.add(.spacer(.small), to: id)
                for kind in ["AI Activity", "System Activity", "Network Activity", "Disk Space", "Battery", "Clock"] { store.add(.widget(kind), to: id) }
                SystemActivityMonitor.shared.setDockVisible(true)
                NetworkActivityMonitor.shared.setDockVisible(true)

            } else {
            store.add(.widget("Clock"), to: id)
            store.add(.widget("Weather"), to: id)
            store.add(.widget("Focus Timer"), to: id)
            store.add(.widget("Sticky Note"), to: id)
            if ProcessInfo.processInfo.environment["MYDOCK_WIDGET_PREVIEW"] == "1" {
                for kind in ["System Activity", "AI Limits", "Disk Space", "Calculator", "Quick Checklist"] { store.add(.widget(kind), to: id) }
                store.add(AIActivityPreviewData.item(), to: id)
            }
            }
            if countdownVisualPreview {
                var countdown = DockItem.widget("Countdown")
                countdown.widgetConfiguration?.setCountdownTarget(Date.now.addingTimeInterval(90_061))
                store.add(countdown, to: id)
            }
            NSApplication.shared.setActivationPolicy(.regular)
            showManager(nil)
            showWindow(id: "visual-preview", title: "Custom Dock Preview",
                       root: VisualDockPreviewSurface(store: store, profileID: id),
                       size: NSSize(width: adaptivePreview ? 1180 : countdownVisualPreview ? 960 : 620,
                                    height: countdownVisualPreview ? 560 : 420))
            showManager(nil)
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
        DiagnosticsService.shared.record(.appLaunched)
        NSApplication.shared.setActivationPolicy(store.state.settings.onboardingComplete ? .accessory : .regular)
        dockController = CustomDockWindowController(store: store) { [weak self] page in
            self?.showSettings(page: page)
        }
        dockController?.update(state: store.state)
        installMenuBarItem()
        let automaticSwitching = AutomaticSwitchingController(store: store)
        self.automaticSwitching = automaticSwitching
        automaticSwitching.start()
        automaticSwitchingObservation = AutomaticSwitchingStatus.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildMenu() }
        stateObservation = store.$state.receive(on: RunLoop.main).sink { [weak self] state in
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
        persistenceObservation = Publishers.CombineLatest(store.$persistenceError, store.$hasUnpersistedChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.rebuildMenu() }
        GlobalShortcutController.shared.onActivateProfile = { [weak self] profileID in
            self?.activateProfile(profileID)
        }
        shortcutObservation = DockShortcutStore.shared.$bindings.receive(on: RunLoop.main).sink { bindings in
            GlobalShortcutController.shared.register(bindings)
        }
        if !store.state.settings.onboardingComplete {
            showOnboarding()
        } else if WhatsNew.shouldShow(settings: store.state.settings) {
            showWhatsNew()
        }
        Task { @MainActor in
            do { try await NativeDockController.shared.recoverInterruptedTransaction(automatic: true) }
            catch { NSLog("MyDock could not recover an interrupted Dock operation: %@", error.localizedDescription) }
            await AlarmNotificationService.reconcileSchedules(in: store)
            await HydrationReminderService.reconcileSchedules(in: store)
        }
        // Hydration reminders can be lost while the Mac sleeps or notification settings change.
        wakeReconcileObservation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let store = self?.store else { return }
                Task { @MainActor in
                    // One-time alarms that rang while the Mac slept turn off, as do any macOS dropped.
                    await AlarmNotificationService.reconcileSchedules(in: store)
                    await HydrationReminderService.reconcileSchedules(in: store)
                }
            }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === windows["workspace"] else { return true }
        return store.editSessions.resolveBeforeQuitting(action: "Close")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        if unitTestHost { return .terminateNow }
        #endif
        if abortingDuplicateLaunch { return .terminateNow }
        DiagnosticsService.shared.record(.quitRequested)
        quitWithoutSaving = false
        let noteResult = WidgetSetupDraftStore.shared.flushNotes(to: store)
        let utilitySaved = store.utilityDrafts.flush()
        guard store.editSessions.resolveBeforeQuitting() else { return .terminateCancel }
        store.flush()
        if store.hasUnpersistedChanges || WidgetSetupDraftStore.shared.hasPendingNotes || !utilitySaved {
            let alert = NSAlert()
            alert.messageText = "MyDock changes are not saved"
            let noteError: String? = { if case .failure(let error) = noteResult { return error.localizedDescription }; return nil }()
            alert.informativeText = noteError ?? store.utilityDrafts.errorMessage ?? store.persistenceError ?? "MyDock could not save its latest changes."
            alert.addButton(withTitle: "Retry Save")
            alert.addButton(withTitle: "Cancel Quit")
            alert.addButton(withTitle: "Quit Without Saving")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                WidgetSetupDraftStore.shared.flushNotes(to: store)
                let draftsSaved = store.utilityDrafts.flush()
                store.commit()
                guard !store.hasUnpersistedChanges, !WidgetSetupDraftStore.shared.hasPendingNotes, draftsSaved else {
                    DiagnosticsService.shared.record(.quitCancelled)
                    return .terminateCancel
                }
            case .alertSecondButtonReturn:
                DiagnosticsService.shared.record(.quitCancelled)
                return .terminateCancel
            case .alertThirdButtonReturn:
                quitWithoutSaving = true
            default:
                DiagnosticsService.shared.record(.quitCancelled)
                return .terminateCancel
            }
        }
        #if DEBUG
        if visualPreview || AppRuntimeEnvironment.isIsolated { return .terminateNow }
        #endif
        guard NativeDockAutoHideController.shared.hasPendingRestore else { return .terminateNow }
        Task { @MainActor in
            do {
                try await NativeDockAutoHideController.shared.restoreBeforeExit()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Apple Dock settings could not be restored"
                alert.informativeText = "MyDock could not restore the Dock's previous visibility settings. The recovery record was kept; try quitting again after resolving the issue.\n\n\(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
                DiagnosticsService.shared.record(.quitCancelled)
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutExecutionService.shared.cancelAll()
        #if DEBUG
        if unitTestHost { return }
        if visualPreview || AppRuntimeEnvironment.isIsolated { try? FileManager.default.removeItem(at: previewDirectory); return }
        #endif
        if !abortingDuplicateLaunch { DiagnosticsService.shared.record(.appTerminated) }
        guard !quitWithoutSaving else { return }
        WidgetSetupDraftStore.shared.flushNotes(to: store)
        if store.hasUnpersistedChanges { store.commit() }
    }

    private func synchronizeCustomMainMode(_ enabled: Bool) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        guard enabled != lastCustomMainModeAttempt || pendingCustomMainMode != nil else { return }
        pendingCustomMainMode = enabled
        guard customMainModeTask == nil else { return }
        customMainModeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let requested = pendingCustomMainMode {
                pendingCustomMainMode = nil
                lastCustomMainModeAttempt = requested
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
        statusItem.button?.image = NSImage(
            systemSymbolName: store.hasUnpersistedChanges ? "exclamationmark.triangle.fill" : "dock.rectangle",
            accessibilityDescription: store.hasUnpersistedChanges ? "MyDock has unsaved changes" : Product.name
        )
        statusItem.button?.title = title ?? ""
        let description = MenuBarProfileTitle.toolTip(in: store.state)
        let persistenceDescription = store.hasUnpersistedChanges
            ? "Changes are waiting to be saved. " + (store.persistenceError ?? "Retry saving in MyDock Settings.")
            : nil
        statusItem.button?.toolTip = [description, persistenceDescription].compactMap { $0 }.joined(separator: "\n")
        statusItem.button?.setAccessibilityLabel([description, persistenceDescription].compactMap { $0 }.joined(separator: ". "))
        let menu = NSMenu()
        if store.hasUnpersistedChanges {
            let item = NSMenuItem(
                title: store.canRetryPersistence ? "Changes Not Saved — Retry Save" : "Changes Not Saved — Settings…",
                action: store.canRetryPersistence ? #selector(retryPersistence(_:)) : #selector(openSettings(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if !store.nativeProfiles.isEmpty {
            let heading = NSMenuItem(title: "macOS Dock", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for profile in store.nativeProfiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.state = DockProfileStatus(profile: profile, settings: store.state.settings).isCurrent ? .on : .off
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
                item.state = DockProfileStatus(profile: profile, settings: store.state.settings).isCurrent ? .on : .off
                menu.addItem(item)
            }
        }
        if let line = AutomaticSwitchingStatus.shared.menuLine {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: "Manage Docks…", action: #selector(openManager(_:)), keyEquivalent: "d"))
        menu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ","))
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

    @objc private func retryPersistence(_ sender: NSMenuItem) {
        store.commit()
    }

    private func activateProfile(_ id: UUID) {
        guard let profile = store.state.profiles.first(where: { $0.id == id }) else { return }
        if profile.kind == .custom {
            store.activate(id)
        } else {
            Task { @MainActor in
                do {
                    try await NativeDockController.shared.apply(profile)
                    store.recordAppliedNativeProfile(id)
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
        showSettings(page: nil)
    }
    private func showSettings(page: MyDockSettingsPage?) {
        workspaceNavigation.showsSettings = true
        if let page { store.updateSettings { $0.lastSettingsPage = page } }
        showWorkspace()
    }
    func showSettingsFromAppMenu() { openSettings(nil) }
    func showManagerFromAppMenu() { showManager(nil) }
    func showAboutFromAppMenu() { openAbout(nil) }
    func showKeyboardShortcutsFromMenu() {
        showWindow(id: "shortcuts", title: "Keyboard Shortcuts",
                   root: KeyboardShortcutsView(onDone: { [weak self] in self?.windows["shortcuts"]?.close() }),
                   size: NSSize(width: 460, height: 560))
    }
    func showWhatsNewFromMenu() { showWhatsNew() }
    private func showWhatsNew() {
        // Marked as seen when shown, so closing the window never brings it back for this version.
        if store.state.settings.lastSeenWhatsNewVersion != Product.marketingVersion {
            store.updateSettings { $0.lastSeenWhatsNewVersion = Product.marketingVersion }
        }
        showWindow(id: "whatsnew", title: "What's New in \(Product.name)",
                   root: WhatsNewView(onContinue: { [weak self] in self?.windows["whatsnew"]?.close() }),
                   size: NSSize(width: 460, height: 520))
    }
    @objc private func openAbout(_ sender: Any?) {
        showWindow(id: "about", title: "About \(Product.name)", root: AboutView(onReplaySetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 420, height: 360))
    }
    @objc private func quit(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    private func showManager(_ sender: Any?) {
        workspaceNavigation.showsSettings = false
        showWorkspace()
    }

    private func showWorkspace() {
        if let window = windows["workspace"] {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        showWindow(id: "workspace", title: "MyDock", root: DockWorkspaceView(store: store, navigation: workspaceNavigation, onContinueSetup: { [weak self] in self?.showOnboarding() }), size: NSSize(width: 1160, height: 760))
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
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.title = title
            window.titlebarAppearsTransparent = true
            window.titleVisibility = id == "workspace" ? .hidden : .visible
            window.toolbarStyle = .unifiedCompact
            window.backgroundColor = NSColor.windowBackgroundColor
            window.hasShadow = true
            window.minSize = id == "workspace" ? NSSize(width: 780, height: 600) : size
            if id == "workspace" { window.delegate = self }
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root.modifier(MyDockInterfaceStyle()))
            window.center()
            windows[id] = window
        }
        window.contentView = NSHostingView(rootView: root.modifier(MyDockInterfaceStyle()))
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
            let settings = store.effectiveSettings(for: profile)
            let scale = CGFloat(settings.customDockSize)
            let model = DockRenderModel(profile: profile, settings: settings, runningApplications: [], windows: [], runningMediaSources: Set(NowPlayingSource.allCases))
            let length = model.contentLength(settings: settings, scale: scale) + (settings.magnificationEnabled ? 32 : 22) * scale
            let horizontal = settings.customDockPosition == .bottom
            ZStack {
                LinearGradient(colors: [DockDesign.accent.opacity(0.16), DockDesign.page],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                DockLayoutPreview(store: store, profile: profile, maximumSideLength: 360, usesLiveData: ProcessInfo.processInfo.environment["MYDOCK_ADAPTIVE_PREVIEW"] == "1")
                    .frame(width: horizontal ? min(length + 20, ProcessInfo.processInfo.environment["MYDOCK_ADAPTIVE_PREVIEW"] == "1" ? 1120 : 560) : 118 * scale)
            }
        }
    }
}
#endif

@MainActor
final class DockWorkspaceNavigation: ObservableObject {
    @Published var showsSettings = false
}

struct DockWorkspaceView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var navigation: DockWorkspaceNavigation
    var onContinueSetup: () -> Void

    @State private var sidebarVisible = true

    var body: some View {
        DockManagerView(store: store, onContinueSetup: onContinueSetup,
                        sidebarVisible: sidebarVisible, showsSettings: navigation.showsSettings,
                        openSettings: { navigation.showsSettings = true },
                        openDocks: { navigation.showsSettings = false })
            .frame(minWidth: 780, minHeight: 560)
            .background(DockDesign.page)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                        .help("Toggle sidebar").accessibilityLabel("Toggle sidebar")
                }
            }
    }
}
