import AppKit
import Combine
import SwiftUI

/// Shared presentation tokens. Dock geometry and provider models remain independent.
enum DockDesign {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let section: CGFloat = 24
        static let page: CGFloat = 32
    }
    enum Motion {
        static let transform = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.86)
        static let reorder = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82)
        static let disclosure = Animation.easeOut(duration: 0.22)
        /// Pointer hover: a quick, nearly critically damped spring.
        static let hover = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// Insertion of modules, sheets and popouts.
        static let appear = Animation.spring(response: 0.38, dampingFraction: 0.86)
        /// Shape and size changes between related states (glass morphs, size pages).
        static let morph = Animation.spring(response: 0.46, dampingFraction: 0.84)
        /// Hover lifts a module by a few percent and brightens it slightly.
        static let hoverScale: CGFloat = 1.03
        static let hoverBrightness: Double = 0.035

        /// The animation to run, or nil when Reduce Motion is on so the change is instant.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }

        /// `withAnimation` that becomes an instant change under Reduce Motion.
        @MainActor
        static func perform<Result>(_ animation: Animation, reduceMotion: Bool, _ body: () throws -> Result) rethrows -> Result {
            if reduceMotion {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                return try withTransaction(transaction, body)
            }
            return try withAnimation(animation, body)
        }
    }
    /// Control Center module metrics: one glyph or number, one short label, at most one more line.
    enum Module {
        /// Today's widget container radius, used when no Dock geometry is known.
        static let defaultRadius: CGFloat = 16
        /// Concentric with the Dock: module radius = Dock radius − Dock padding, never negative.
        static func radius(dockRadius: CGFloat, dockPadding: CGFloat) -> CGFloat {
            guard dockRadius.isFinite, dockPadding.isFinite else { return 0 }
            return max(0, dockRadius - dockPadding)
        }
        /// Content insets inside a module.
        static let insets = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        /// Vertical gap between value and label.
        static let lineSpacing: CGFloat = 2
        enum Glyph {
            static let large: CGFloat = 22
            static let medium: CGFloat = 17
        }
        enum ValueSize: CaseIterable { case large, medium, small }
        /// SF Pro semibold with tabular digits so changing numbers do not jitter.
        static func value(_ size: ValueSize) -> Font {
            switch size {
            case .large: valueLarge
            case .medium: valueMedium
            case .small: valueSmall
            }
        }
        static func pointSize(_ size: ValueSize) -> CGFloat {
            switch size { case .large: 22; case .medium: 18; case .small: 13 }
        }
        static let valueLarge = Font.system(size: 22, weight: .semibold).monospacedDigit()
        static let valueMedium = Font.system(size: 18, weight: .semibold).monospacedDigit()
        static let valueSmall = Font.system(size: 13, weight: .semibold).monospacedDigit()
        /// Short label under the value; draw it with `.secondary`.
        static let label = Font.system(size: 11, weight: .medium)
        static let labelLarge = Font.system(size: 12, weight: .medium)
        /// Smallest text the redesign draws anywhere.
        static let minimumTextSize: CGFloat = 10
        static let maxTextLines = 2
    }
    /// Liquid Glass with accessible fallbacks. Apply it with `View.dockGlass(_:in:tint:interactive:)`.
    enum Glass {
        enum Style: Hashable, CaseIterable { case clear, regular }
        /// Opaque surfaces under Reduce Transparency; the same values WidgetContainer uses.
        static func opaqueFill(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)
        }
        /// The Midnight finish: one deep blue-grey for the Dock and its style swatch.
        static let midnightFill = Color(red: 0.10, green: 0.12, blue: 0.16)
        /// Strength of a tint mixed into fallback and opaque surfaces.
        static let fallbackTintOpacity: Double = 0.18
    }
    /// Inset grouped form metrics (System Settings on macOS 26).
    enum Grouped {
        static let radius: CGFloat = 12
        static let rowMinHeight: CGFloat = 36
        static let rowHorizontalPadding: CGFloat = 12
        static let rowVerticalPadding: CGFloat = 7
        static let glyphSize: CGFloat = 22
        static let glyphRadius: CGFloat = 6
        static let glyphSpacing: CGFloat = 10
        /// Separators start where the row title starts.
        static var separatorInset: CGFloat { rowHorizontalPadding + glyphSize + glyphSpacing }
        static let headerFont = Font.system(size: 13, weight: .semibold)
        static let footerFont = Font.system(size: 11)
        static let titleFont = Font.system(size: 13)
        static let subtitleFont = Font.system(size: 11)
        static let fill = adaptive("grouped", dark: 0x26272b, light: 0xffffff)
        static let separator = Color.primary.opacity(0.09)
    }
    enum Radius {
        static let control: CGFloat = 7
        static let input: CGFloat = 8
        static let row: CGFloat = 8
        static let group: CGFloat = 12
        /// Large previews such as the Appearance hero.
        static let preview: CGFloat = 14
    }
    /// Keep normal outlines quiet, with stronger boundaries for Increase Contrast.
    enum Outline {
        static func color(_ contrast: ColorSchemeContrast) -> Color {
            Color.primary.opacity(contrast == .increased ? 0.55 : 0.08)
        }
        static func controlWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
            contrast == .increased ? 1 : 0.5
        }
        static func dockWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
            contrast == .increased ? 2 : 1
        }
    }
    static let sidebarWidth: CGFloat = 204
    static let rowHeight: CGFloat = 40
    static let controlHeight: CGFloat = 30
    static let settingsWidth: CGFloat = 820
    static let title = Font.system(size: 30, weight: .semibold)
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let accent = Color(nsColor: .systemBlue)
    static let page = adaptive("page", dark: 0x131416, light: 0xf5f5f7)
    static let sidebar = adaptive("sidebar", dark: 0x191a1d, light: 0xeeeef0)
    static let card = adaptive("surface", dark: 0x202125, light: 0xffffff)
    static let input = adaptive("input", dark: 0x242529, light: 0xffffff)
    static let hover = Color.primary.opacity(0.05)
    static let selection = Color.primary.opacity(0.065)
    static let control = adaptive("control", dark: 0x303135, light: 0xe8e8eb)
    static let hairline = Color.primary.opacity(0.08)

    private static func adaptive(_ name: String, dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("MyDock." + name)) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

/// Shared accessibility presentation state. Render-only overrides are absent
/// from Release builds and never modify the Mac's accessibility preferences.
@propertyWrapper
struct DockAccessibilityStyle: DynamicProperty {
    var wrappedValue: DockAccessibilityStyle { self }
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    #if DEBUG
    @Environment(\.dockAccessibilityPreview) private var preview
    #endif
    var contrast: ColorSchemeContrast {
        #if DEBUG
        if let preview { return preview.contrast }
        #endif
        return systemContrast
    }
    var reduceTransparency: Bool {
        #if DEBUG
        if let preview { return preview.reduceTransparency }
        #endif
        return systemReduceTransparency
    }
    var reduceMotion: Bool {
        #if DEBUG
        if let preview { return preview.reduceMotion }
        #endif
        return systemReduceMotion
    }
    /// Convenience for `DockDesign.Motion.animation(_:reduceMotion:)`.
    func animation(_ animation: Animation) -> Animation? {
        DockDesign.Motion.animation(animation, reduceMotion: reduceMotion)
    }
}
#if DEBUG
struct DockAccessibilityPreview {
    var contrast: ColorSchemeContrast
    var reduceTransparency: Bool
    var reduceMotion: Bool = false
}
private struct DockAccessibilityPreviewKey: EnvironmentKey {
    static let defaultValue: DockAccessibilityPreview? = nil
}
extension EnvironmentValues {
    var dockAccessibilityPreview: DockAccessibilityPreview? {
        get { self[DockAccessibilityPreviewKey.self] }
        set { self[DockAccessibilityPreviewKey.self] = newValue }
    }
}
#endif

enum MyDockInterfaceAppearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .dark: .dark; case .light: .light } }
    var native: NSAppearance? { switch self { case .system: nil; case .dark: NSAppearance(named: .darkAqua); case .light: NSAppearance(named: .aqua) } }
    static let preferenceKey = "app.mydock.interface-appearance"
    static var current: Self { Self(rawValue: AppRuntimeEnvironment.defaults.string(forKey: preferenceKey) ?? "system") ?? .system }
}

/// The floating Dock's System theme follows macOS independently of the editor.
@MainActor
final class DockSystemAppearance: ObservableObject {
    static let shared = DockSystemAppearance()
    @Published private(set) var scheme: ColorScheme = AppRuntimeEnvironment.defaults.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    private var observation: AnyCancellable?
    private init() {
        observation = DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheme = AppRuntimeEnvironment.defaults.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
                }
            }
    }
}

struct MyDockInterfaceStyle: ViewModifier {
    @AppStorage(MyDockInterfaceAppearance.preferenceKey, store: AppRuntimeEnvironment.defaults) private var appearance = "system"
    private var selected: MyDockInterfaceAppearance {
        #if DEBUG
        if let dark = ProcessInfo.processInfo.environment["MYDOCK_VISUAL_DARK"],
           ProcessInfo.processInfo.environment["MYDOCK_VISUAL_PREVIEW"] == "1" {
            return dark == "1" ? .dark : .light
        }
        #endif
        return .init(rawValue: appearance) ?? .system
    }
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(selected.colorScheme)
            .font(DockDesign.body)
            .tint(DockDesign.accent)
            .controlSize(.regular)
            .buttonStyle(DockButtonStyle())
            .textFieldStyle(DockTextFieldStyle())
            .onAppear { NSApplication.shared.appearance = selected.native }
            .onChange(of: appearance) { _ in NSApplication.shared.appearance = selected.native }
    }
}

struct AppSurface: ViewModifier {
    @DockAccessibilityStyle() private var accessibility
    private var contrast: ColorSchemeContrast { accessibility.contrast }
    var radius: CGFloat = DockDesign.Radius.group
    func body(content: Content) -> some View {
        content.background(DockDesign.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DockDesign.Outline.color(contrast), lineWidth: DockDesign.Outline.controlWidth(contrast)))
    }
}

struct DockButtonStyle: ButtonStyle {
    var primary = false
    var icon = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        DockButtonBody(configuration: configuration, primary: primary, icon: icon, enabled: enabled)
    }
    private struct DockButtonBody: View {
        let configuration: ButtonStyle.Configuration
        var primary: Bool
        var icon: Bool
        var enabled: Bool
        @State private var hovered = false
        @DockAccessibilityStyle() private var accessibility
        private var contrast: ColorSchemeContrast { accessibility.contrast }
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: primary ? .semibold : .regular))
                .foregroundStyle(primary ? Color.white : Color.primary.opacity(0.9))
                .padding(.horizontal, icon ? 8 : 12)
                .frame(minWidth: icon ? 30 : nil, minHeight: DockDesign.controlHeight)
                .background(primary ? DockDesign.accent : (hovered ? DockDesign.control : DockDesign.card),
                            in: RoundedRectangle(cornerRadius: DockDesign.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.control)
                    .strokeBorder(contrast == .increased ? DockDesign.Outline.color(contrast) : primary ? Color.white.opacity(0.08) : DockDesign.hairline, lineWidth: DockDesign.Outline.controlWidth(contrast)))
                .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.control).fill(.black.opacity(configuration.isPressed ? 0.16 : 0)))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: DockDesign.Radius.control))
                .onHover { hovered = $0 }
        }
    }
}

@MainActor
struct DockTextFieldStyle: @preconcurrency TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        DockInputBody(content: configuration)
    }
    private struct DockInputBody<Content: View>: View {
        var content: Content
        @FocusState private var focused: Bool
        @DockAccessibilityStyle() private var accessibility
        private var contrast: ColorSchemeContrast { accessibility.contrast }
        var body: some View {
            content.textFieldStyle(.plain).padding(.horizontal, 10).frame(height: 32)
                .background(DockDesign.input, in: RoundedRectangle(cornerRadius: DockDesign.Radius.input))
                .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.input)
                    .strokeBorder(focused ? DockDesign.accent : DockDesign.Outline.color(contrast), lineWidth: focused ? 2 : DockDesign.Outline.controlWidth(contrast)))
                .focused($focused)
        }
    }
}

struct DockSearchField: View {
    var placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @DockAccessibilityStyle() private var accessibility
    private var contrast: ColorSchemeContrast { accessibility.contrast }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 10).frame(height: 32)
            .background(DockDesign.input, in: RoundedRectangle(cornerRadius: DockDesign.Radius.input))
            .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.input)
                .strokeBorder(focused ? DockDesign.accent : DockDesign.Outline.color(contrast), lineWidth: focused ? 2 : DockDesign.Outline.controlWidth(contrast)))
    }
}

struct SidebarRow<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            content.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(minHeight: DockDesign.rowHeight)
                .background(selected ? DockDesign.selection : (hovered ? DockDesign.hover : .clear),
                            in: RoundedRectangle(cornerRadius: DockDesign.Radius.row))
                .contentShape(RoundedRectangle(cornerRadius: DockDesign.Radius.row))
        }.buttonStyle(.plain)
            .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.75))
            .onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SidebarSectionTitle: View {
    var title: String
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 6)
    }
}

struct DockSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct DockSidebarHeader<Accessory: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(DockDesign.accent).frame(width: 28, height: 28)
            Text(title).font(.system(size: 19, weight: .semibold))
            Spacer(minLength: 0)
            accessory
        }.padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 18)
    }
}

struct DockScreenHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !eyebrow.isEmpty { Text(eyebrow).font(DockDesign.caption).foregroundStyle(.secondary) }
            Text(title).font(DockDesign.title)
            Text(subtitle).font(DockDesign.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControlRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        GroupedRow(title) {
            content.labelsHidden().frame(maxWidth: 260, alignment: .trailing)
        }
    }
}

struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.accessibilityHidden(true).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(minHeight: DockDesign.Grouped.rowMinHeight)
    }
}

struct SettingsPageHeader: View {
    var page: MyDockSettingsPage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title).font(DockDesign.pageTitle)
            Text(page.designDescription).font(DockDesign.body).foregroundStyle(.secondary)
                .lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }
}

struct SettingsSidebarLabel: View {
    var page: MyDockSettingsPage
    var body: some View {
        HStack(spacing: 10) {
            GroupedRowGlyph(symbol: page.symbol, color: page.designColor, size: 26)
            Text(page.title).font(DockDesign.body)
        }
    }
}

extension MyDockSettingsPage {
    var designColor: Color {
        switch self { case .general: .gray; case .dock: .blue; case .appearance: .purple; case .behavior: .orange; case .shortcuts: .pink; case .integrations: .green; case .permissions: .blue }
    }
    var designDescription: String {
        switch self {
        case .general: "Manage your saved layouts, backups, and app preferences."
        case .dock: "Choose your Dock, its screen, and its position."
        case .appearance: "Make your Dock feel at home on your Mac."
        case .behavior: "Choose what appears and how your Dock responds."
        case .shortcuts: "Switch to your favorite layouts from the keyboard."
        case .integrations: "Connect the services you use in your widgets."
        case .permissions: "Control which features can access your Mac."
        }
    }
}

extension DockProfileColor {
    var displayColor: Color {
        switch self {
        case .blue: .init(red: 0.30, green: 0.49, blue: 0.82)
        case .purple: .init(red: 0.57, green: 0.44, blue: 0.78)
        case .teal: .init(red: 0.25, green: 0.61, blue: 0.62)
        case .green: .init(red: 0.37, green: 0.62, blue: 0.45)
        case .orange: .init(red: 0.85, green: 0.55, blue: 0.29)
        case .pink: .init(red: 0.79, green: 0.44, blue: 0.59)
        case .red: .init(red: 0.79, green: 0.36, blue: 0.37)
        }
    }
}

/// Native scrolling in the app. DEBUG snapshots flatten the viewport because
/// AppKit's scroll compositor cannot be cached by an offscreen NSHostingView.
struct DockScrollView<Content: View>: View {
    var axes: Axis.Set
    var showsIndicators: Bool
    var content: Content
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #endif
    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    @ViewBuilder var body: some View {
        #if DEBUG
        if snapshotRendering {
            content.fixedSize(horizontal: axes.contains(.horizontal), vertical: axes.contains(.vertical))
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading).clipped()
        } else {
            ScrollView(axes, showsIndicators: showsIndicators) { content }
        }
        #else
        ScrollView(axes, showsIndicators: showsIndicators) { content }
        #endif
    }
}

#if DEBUG
private struct DockSnapshotRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var dockSnapshotRendering: Bool {
        get { self[DockSnapshotRenderingKey.self] }
        set { self[DockSnapshotRenderingKey.self] = newValue }
    }
}
#endif
