import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: ProfileStore
    var onFinish: () -> Void

    @State private var step = 0
    @State private var setupMode: SetupMode
    @State private var dockPosition: DockPosition
    @State private var displayID: UInt32?
    @State private var importCurrentDock = true
    @State private var includeStarterApps = true
    @State private var starterWidgets: Set<String> = ["Clock", "Battery"]
    @State private var importError: String?
    /// The appearance before setup applied Clear; set once setup is saved, it shows the reveal.
    @State private var revealBaseline: AppSettings?
    /// First run only: replaying setup never changes an existing Dock's look.
    private let appliesClearStyle: Bool
    /// The "Your Dock, clearer" reveal after the four setup steps.
    static let revealStep = 4

    init(store: ProfileStore, initialStep: Int = 0, onFinish: @escaping () -> Void) {
        self.store = store
        _step = State(initialValue: min(3, max(0, initialStep)))
        self.onFinish = onFinish
        _setupMode = State(initialValue: store.state.settings.setupMode)
        _dockPosition = State(initialValue: store.state.settings.customDockPosition)
        _displayID = State(initialValue: store.state.settings.customDockDisplayID)
        appliesClearStyle = !store.state.settings.onboardingComplete
    }

    #if DEBUG
    /// Render-only: opens directly on the reveal, morphing from `baseline` to the store's look.
    init(store: ProfileStore, revealingFrom baseline: AppSettings, onFinish: @escaping () -> Void) {
        self.init(store: store, onFinish: onFinish)
        _step = State(initialValue: Self.revealStep)
        _revealBaseline = State(initialValue: baseline)
    }
    #endif

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label("MyDock", systemImage: "dock.rectangle").font(.system(size: 21, weight: .semibold))
                    .padding(.top, 32).padding(.bottom, 8)
                Text("Make room for what matters.").font(DockDesign.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 32)
                ForEach(Array(["Welcome", "Your Dock", "Placement", "Review"].enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 10) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle")
                            .foregroundStyle(index == step ? DockDesign.accent : Color.secondary).frame(width: 20)
                        Text(title).font(DockDesign.body)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(index == step ? DockDesign.selection : .clear, in: RoundedRectangle(cornerRadius: DockDesign.Radius.row))
                        .foregroundStyle(index <= step ? Color.primary : Color.secondary)
                        .padding(.bottom, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(index + 1), \(title)")
                        .accessibilityValue(index < step ? "Done" : index == step ? "Current" : "")
                }
                Spacer()
                Text("Set up once. Refine anytime.").font(DockDesign.Grouped.footerFont).foregroundStyle(.tertiary)
            }.padding(.horizontal, 20).padding(.bottom, 24).frame(width: 212).background(DockDesign.sidebar)
            Rectangle().fill(DockDesign.hairline).frame(width: 1)
            if step == Self.revealStep, let revealBaseline {
                OnboardingClearReveal(store: store, baseline: revealBaseline, onDone: onFinish)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            VStack(alignment: .leading, spacing: 24) {
                DockScreenHeader(eyebrow: "Step \(step + 1) of 4", title: stepTitle, subtitle: stepSubtitle)
                DockScrollView {
                    Group {
                        switch step {
                        case 0: modeStep
                        case 1: profilesStep
                        case 2: placementStep
                        default: reviewStep
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    if step > 0 { Button("Back") { step -= 1 } }
                    Spacer()
                    Button(step < 3 ? "Continue" : "Finish Setup") {
                        if step < 3 { step += 1 } else { finish() }
                    }.buttonStyle(DockButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 740, minHeight: 540)
        .background(DockDesign.page).buttonStyle(DockButtonStyle())
        .tint(DockDesign.accent).font(DockDesign.body).toggleStyle(SettingsSwitchStyle())
        .alert("Could not finish setup", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private var stepTitle: String {
        switch step {
        case 0: "Welcome to MyDock"
        case 1: "Make it yours"
        case 2: "Find its place"
        default: "You're ready"
        }
    }
    private var stepSubtitle: String {
        switch step {
        case 0: "Choose how you'd like to use your Dock."
        case 1: "Start with your apps and a few useful widgets."
        case 2: "Choose the screen and edge that work for you."
        default: "Review your choices. You can change them any time."
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SetupMode.allCases) { mode in
                Button { setupMode = mode } label: {
                    HStack(spacing: 12) {
                        Image(systemName: setupMode == mode ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 16)).foregroundStyle(setupMode == mode ? DockDesign.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title).font(DockDesign.sectionTitle)
                            Text(description(for: mode)).font(DockDesign.body).foregroundStyle(.secondary)
                            Text(DockProfileStatus.nativeConsequence(for: mode)).font(DockDesign.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(12).frame(minHeight: 88).contentShape(Rectangle())
                    .background(setupMode == mode ? DockDesign.selection : DockDesign.card, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.group, style: .continuous)
                        .stroke(DockDesign.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(setupMode == mode ? .isSelected : [])
            }
        }
    }

    private var profilesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start with a Dock").font(DockDesign.sectionTitle)
            if setupMode != .customMain {
                if store.nativeProfiles.isEmpty {
                    Toggle("Import my current macOS Dock", isOn: $importCurrentDock)
                    Text("MyDock reads your pinned apps and spacer order. It does not apply changes to the macOS Dock during setup.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Your existing macOS Docks will be kept.")
                        .font(DockDesign.body).foregroundStyle(.secondary)
                }
            }
            if setupMode != .nativeOnly {
                if store.customProfiles.isEmpty {
                    Text("Choose starter widgets for your Custom Dock.")
                    Toggle("Include installed starter apps", isOn: $includeStarterApps)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 144))], spacing: 8) {
                        ForEach(Self.starterWidgetNames, id: \.self) { name in
                            let selected = starterWidgets.contains(name)
                            Button {
                                if selected { starterWidgets.remove(name) }
                                else { starterWidgets.insert(name) }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    WidgetCardPreview(kind: name, width: 128).accessibilityHidden(true)
                                    HStack {
                                        Text(name).font(DockDesign.caption)
                                        Spacer()
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? DockDesign.accent : Color.secondary)
                                            .accessibilityHidden(true)
                                    }
                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected ? DockDesign.selection : DockDesign.card, in: RoundedRectangle(cornerRadius: DockDesign.Radius.row))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                } else {
                    Text("Your existing Custom Dock will be kept. Starter widget choices apply when setup creates a new Dock.")
                        .font(DockDesign.body).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label("You can add, remove, or change Docks later in Manage Docks.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var placementStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if setupMode == .nativeOnly {
                Text("macOS Dock only").font(DockDesign.sectionTitle)
                Text("No Custom Dock placement is needed for this setup. You can add a Custom Dock later from Manage Docks.")
                    .font(DockDesign.body).foregroundStyle(.secondary)
            } else {
                Text("Choose the Custom Dock placement.").font(DockDesign.sectionTitle)
                SettingsControlRow(title: "Position") {
                    Picker("Edge", selection: $dockPosition) {
                        ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 200)
                }
                SettingsControlRow(title: "Display") {
                    Picker("Display", selection: $displayID) {
                        Text("Main display").tag(Optional<UInt32>.none)
                        ForEach(displayOptions) { option in Text(option.title).tag(Optional(option.id)) }
                    }
                }
                placementPreview
                Text("Placement, display, size, and auto-hide can be changed later in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var placementPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Placement preview").font(DockDesign.sectionTitle)
            ZStack(alignment: dockPosition == .bottom ? .bottom : (dockPosition == .left ? .leading : .trailing)) {
                RoundedRectangle(cornerRadius: DockDesign.Radius.group).fill(DockDesign.sidebar)
                    .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.group).strokeBorder(DockDesign.hairline, lineWidth: 0.5))
                Group {
                    if dockPosition == .bottom {
                        HStack(spacing: 10) { previewIcons }
                    } else {
                        VStack(spacing: 6) { previewIcons }
                    }
                }
                .padding(9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(14)
            }
            .frame(height: 160)
            Text(previewSummary).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

    }

    @ViewBuilder private var previewIcons: some View {
        ForEach(["folder", "globe", "timer", "calendar"], id: \.self) { symbol in
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 27, height: 27)
                .background(DockDesign.card, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to use MyDock").font(DockDesign.sectionTitle)
            Label(setupMode.title, systemImage: "checkmark.circle")
            if setupMode != .nativeOnly {
                Label("Custom Dock at the \(dockPosition.title.lowercased()) edge", systemImage: "rectangle.bottomthird.inset.filled")
                if store.customProfiles.isEmpty {
                    let widgets = Self.starterWidgetKinds(starterWidgets, for: setupMode)
                    Text("Starter widgets: \(widgets.isEmpty ? "None selected" : widgets.joined(separator: ", "))")
                        .font(DockDesign.body).foregroundStyle(.secondary)
                } else {
                    Text("Your existing Custom Dock will be kept.")
                        .font(DockDesign.body).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Permissions are optional and requested only when you use a feature that needs them.")
                .font(DockDesign.sectionTitle)
            Text("Hydration reminders may request Notifications. Calendar, Reminders, Weather location, Accessibility, and Screen Recording are not needed for this setup. You can review optional permissions in Settings.")
                .font(DockDesign.body).foregroundStyle(.secondary)
            Spacer()
            Label(DockProfileStatus.nativeConsequence(for: setupMode), systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var displayOptions: [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayChoice(id: number.uint32Value, title: screen.localizedName)
        }
    }

    private var previewSummary: String {
        let screen = displayOptions.first(where: { $0.id == displayID })?.title ?? "Main display"
        let profileSummary = store.customProfiles.isEmpty ? "\(Self.starterWidgetKinds(starterWidgets, for: setupMode).count) starter widget(s)" : "existing Dock"
        return "\(dockPosition.title) · \(screen) · \(profileSummary)"
    }

    private func description(for mode: SetupMode) -> String {
        switch mode {
        case .nativeOnly: "Save and switch arrangements of the macOS Dock."
        case .both: "Use saved macOS Docks alongside a separate Custom Dock."
        case .customMain: "Use MyDock for apps and widgets. The macOS Dock stays hidden, including at the screen edge."
        }
    }

    private func finish() {
        let importedItems: [DockItem]
        // An existing macOS Dock is kept, so nothing is read (or can block setup) for it.
        if setupMode == .customMain || !importCurrentDock || !store.nativeProfiles.isEmpty {
            importedItems = []
        } else {
            do {
                importedItems = try NativeDockController.shared.readCurrentItems()
            } catch {
                importError = "Your setup was not saved. You can turn off “Import my current macOS Dock” and continue, or try again. \(error.localizedDescription)"
                return
            }
        }
        let baseline = store.state.settings
        let result = OnboardingCompletion.finish(store: store, appliesClearStyle: appliesClearStyle) {
            try store.finishOnboarding(setupMode: setupMode,
                                   customDockPosition: dockPosition,
                                   customDockDisplayID: displayID,
                                   importedNativeItems: importedItems,
                                   starterWidgets: Self.starterWidgetKinds(starterWidgets, for: setupMode),
                                   starterApplications: includeStarterApps ? DockStarterPreset.everyday.items().filter { $0.type == .application } : [])
        }
        if let error = result.error {
            importError = error
            return
        }
        // Setup is saved. A Custom Dock that just became Clear gets the reveal; Done closes.
        guard result.appliedClearStyle, setupMode != .nativeOnly else { onFinish(); return }
        revealBaseline = baseline
        step = Self.revealStep
    }

    /// Replacing Apple's Dock also hides its Trash, so a new replacement Dock ends with one.
    static func starterWidgetKinds(_ chosen: Set<String>, for mode: SetupMode) -> [String] {
        var widgets = chosen.sorted()
        if mode == .customMain, !widgets.contains("Trash") { widgets.append("Trash") }
        return widgets
    }

    private static let starterWidgetNames = ["Clock", "World Clock", "Stopwatch", "Countdown", "Time Progress", "Focus Timer", "Sticky Note", "Hydration", "Battery"]
}

/// Finishing setup. On first run the Clear style is applied and persisted first, through the
/// same settings path as the Appearance page; setup is then persisted, and completion is
/// published only by that successful write. Any failure rolls Clear back, so a failed setup
/// keeps the previous look.
@MainActor
enum OnboardingCompletion {
    struct Result: Equatable {
        var error: String?
        var appliedClearStyle = false
    }

    static let saveFailure = "Setup could not be saved. Retry after restoring access to your data folder."

    static func finish(store: ProfileStore, appliesClearStyle: Bool, persistSetup: () throws -> Void) -> Result {
        let previous = store.state.settings
        func rollBack() {
            guard appliesClearStyle else { return }
            store.updateSettings(immediately: true) { $0 = previous }
        }
        if appliesClearStyle {
            store.updateSettings(immediately: true) { DockQuickStyle.clear.apply(to: &$0) }
            guard !store.hasUnpersistedChanges else {
                let error = store.persistenceError ?? saveFailure
                rollBack()
                return Result(error: error)
            }
        }
        do { try persistSetup() } catch {
            rollBack()
            return Result(error: error.localizedDescription)
        }
        // Secondary guard: the write itself succeeded, so these flags should agree.
        guard !store.hasUnpersistedChanges, store.state.settings.onboardingComplete else {
            let error = store.persistenceError ?? saveFailure
            rollBack()
            return Result(error: error)
        }
        return Result(appliedClearStyle: appliesClearStyle)
    }
}

/// "Your Dock, clearer": the user's new Custom Dock morphs from today's look into Clear.
struct OnboardingClearReveal: View {
    @ObservedObject var store: ProfileStore
    /// The settings before setup applied Clear.
    var baseline: AppSettings
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            OnboardingClearRevealHero(store: store, baseline: baseline)
            VStack(spacing: 6) {
                Text("Your Dock, clearer").font(DockDesign.title)
                Text("Clear glass and quiet widgets. Change the style anytime in Settings.")
                    .font(DockDesign.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            PillButton("Done", action: onDone).keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .padding(32)
    }
}

/// The reveal's hero: a sample-data preview of the user's Custom Dock. It starts in `baseline`
/// and morphs into the saved look on `Motion.morph`; under Reduce Motion it shows Clear at once.
struct OnboardingClearRevealHero: View {
    @ObservedObject var store: ProfileStore
    var baseline: AppSettings
    /// Render-only: pin the start (false) or end (true) frame.
    var phase: Bool?
    @State private var revealed = false
    @DockAccessibilityStyle() private var accessibility
    static let previewSize = 0.7

    init(store: ProfileStore, baseline: AppSettings, phase: Bool? = nil) {
        self.store = store
        self.baseline = baseline
        self.phase = phase
    }

    private var profile: DockProfile {
        store.activeCustomProfile ?? store.customProfiles.first
            ?? DockProfile(name: "Custom Dock", kind: .custom, items: [.widget("Clock"), .widget("Battery")])
    }

    var body: some View {
        let shown = phase ?? (revealed || accessibility.reduceMotion)
        var preview = profile
        var appearance = ProfileAppearance(settings: shown ? store.effectiveSettings(for: profile) : baseline)
        // Preview-only: a smaller Dock so a starter Dock fits the setup window without scrolling.
        appearance.size = min(appearance.size, Self.previewSize)
        preview.appearance = appearance
        return ZStack {
            SwatchWallpaper()
            DockLayoutPreview(store: store, profile: preview, maximumSideLength: 200)
                .padding(20)
        }
        .frame(maxWidth: 520).frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Custom Dock in the Clear style, sample preview")
        .task {
            guard phase == nil, !revealed else { return }
            // A beat on today's look first, so the change reads as a reveal.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) { revealed = true }
        }
    }
}

private struct DisplayChoice: Identifiable {
    var id: UInt32
    var title: String
}
