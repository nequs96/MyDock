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
    @State private var starterWidgets: Set<String> = ["Clock", "Battery"]

    init(store: ProfileStore, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        _setupMode = State(initialValue: store.state.settings.setupMode)
        _dockPosition = State(initialValue: store.state.settings.customDockPosition)
        _displayID = State(initialValue: store.state.settings.customDockDisplayID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DockScreenHeader(eyebrow: "STEP \(step + 1) OF 4", title: "Your Dock, your way.",
                             subtitle: "A few choices will make MyDock feel at home on your Mac.")
            HStack(spacing: 7) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index <= step ? DockDesign.accent : Color.secondary.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .padding(.top, 16).padding(.bottom, 24)

            ScrollView {
                Group {
                    switch step {
                    case 0: modeStep
                    case 1: profilesStep
                    case 2: placementStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().padding(.top, 14)
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 3 {
                    Button("Continue") { step += 1 }.buttonStyle(.borderedProminent)
                } else {
                    Button("Finish Setup") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 14)
        }
        .padding(30)
        .frame(minWidth: 720, minHeight: 560)
        .background(DockDesign.page)
        .tint(DockDesign.accent)
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose how you want to use your Dock.").font(.title3.weight(.semibold))
            ForEach(SetupMode.allCases) { mode in
                Button { setupMode = mode } label: {
                    HStack(spacing: 14) {
                        Image(systemName: setupMode == mode ? "largecircle.fill.circle" : "circle")
                            .font(.title2).foregroundStyle(setupMode == mode ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title).font(.headline)
                            Text(description(for: mode)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16).contentShape(Rectangle())
                    .background(DockDesign.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(setupMode == mode ? DockDesign.accent : DockDesign.hairline,
                                lineWidth: setupMode == mode ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profilesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start with a profile").font(.title3.weight(.semibold))
            if setupMode != .customMain {
                Toggle("Import my current macOS Dock", isOn: $importCurrentDock)
                Text("MyDock reads your pinned apps and spacer order. It does not apply changes to the macOS Dock during setup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if setupMode != .nativeOnly {
                if store.customProfiles.isEmpty {
                    Text("Choose starter widgets for your Custom Dock.")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Self.starterWidgetNames, id: \.self) { name in
                            let selected = starterWidgets.contains(name)
                            Button {
                                if selected { starterWidgets.remove(name) }
                                else { starterWidgets.insert(name) }
                            } label: {
                                Label(name, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(DockDesign.card, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected ? DockDesign.accent : DockDesign.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Your existing Custom Dock profile will be kept. Starter widget choices apply when setup creates a new profile.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label("You can add, remove, or change profiles later in Manage Docks.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var placementStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if setupMode == .nativeOnly {
                Text("macOS Dock only").font(.title3.weight(.semibold))
                Text("No Custom Dock placement is needed for this setup. You can add a Custom Dock later from Manage Docks.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Choose the Custom Dock placement.").font(.title3.weight(.semibold))
                Picker("Edge", selection: $dockPosition) {
                    ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Display", selection: $displayID) {
                    Text("Main display").tag(Optional<UInt32>.none)
                    ForEach(displayOptions) { option in Text(option.title).tag(Optional(option.id)) }
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
            Text("Placement preview").font(.headline)
            ZStack(alignment: dockPosition == .bottom ? .bottom : (dockPosition == .left ? .leading : .trailing)) {
                RoundedRectangle(cornerRadius: 16).fill(DockDesign.accent.opacity(0.1))
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
            .frame(height: 186)
            Text(previewSummary).font(.caption).foregroundStyle(.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DockDesign.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DockDesign.hairline))
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
            Text("Ready to use MyDock").font(.title3.weight(.semibold))
            Label(setupMode.title, systemImage: "checkmark.circle")
            if setupMode != .nativeOnly {
                Label("Custom Dock at the \(dockPosition.title.lowercased()) edge", systemImage: "rectangle.bottomthird.inset.filled")
                if store.customProfiles.isEmpty {
                    Text("Starter widgets: \(starterWidgets.sorted().joined(separator: ", ").isEmpty ? "None selected" : starterWidgets.sorted().joined(separator: ", "))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Your existing Custom Dock profile will be kept.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Permissions are optional and requested only when you use a feature that needs them.")
                .font(.headline)
            Text("Hydration reminders may request Notifications. Calendar, Reminders, Weather location, Accessibility, and Screen Recording are not needed for this setup. You can review optional permissions in Settings.")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Label("No changes will be made to the macOS Dock until you explicitly apply a native profile.", systemImage: "lock.shield")
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
        let profileSummary = store.customProfiles.isEmpty ? "\(starterWidgets.count) starter widget(s)" : "existing profile"
        return "\(dockPosition.title) · \(screen) · \(profileSummary)"
    }

    private func description(for mode: SetupMode) -> String {
        switch mode {
        case .nativeOnly: "Manage saved layouts for Apple's Dock."
        case .both: "Use saved macOS Dock profiles alongside a separate Custom Dock."
        case .customMain: "Use MyDock's own launcher and widgets as your primary Dock-like surface."
        }
    }

    private func finish() {
        let importedItems = setupMode == .customMain || !importCurrentDock
            ? [] : NativeDockController.shared.readCurrentItems()
        store.finishOnboarding(setupMode: setupMode,
                               customDockPosition: dockPosition,
                               customDockDisplayID: displayID,
                               importedNativeItems: importedItems,
                               starterWidgets: starterWidgets.sorted())
        onFinish()
    }

    private static let starterWidgetNames = ["Clock", "World Clock", "Stopwatch", "Countdown", "Time Progress", "Focus Timer", "Sticky Note", "Hydration", "Battery"]
}

private struct DisplayChoice: Identifiable {
    var id: UInt32
    var title: String
}
