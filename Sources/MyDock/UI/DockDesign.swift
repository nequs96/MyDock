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
    }
    enum Radius {
        static let control: CGFloat = 7
        static let input: CGFloat = 8
        static let row: CGFloat = 8
        static let group: CGFloat = 12
        static let preview: CGFloat = 14
        static let floating: CGFloat = 14
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
}
#if DEBUG
struct DockAccessibilityPreview {
    var contrast: ColorSchemeContrast
    var reduceTransparency: Bool
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
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system }
}

/// The floating Dock's System theme follows macOS independently of the editor.
@MainActor
final class DockSystemAppearance: ObservableObject {
    static let shared = DockSystemAppearance()
    @Published private(set) var scheme: ColorScheme = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    private var observation: AnyCancellable?
    private init() {
        observation = DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheme = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
                }
            }
    }
}

struct MyDockInterfaceStyle: ViewModifier {
    @AppStorage(MyDockInterfaceAppearance.preferenceKey) private var appearance = "system"
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

struct DockSettingSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DockDesign.sectionTitle).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .overlay(alignment: .top) { Rectangle().fill(DockDesign.hairline).frame(height: 1) }
                .toggleStyle(SettingsSwitchStyle())
                .controlSize(.small)
                .buttonStyle(DockButtonStyle())
                .textFieldStyle(DockTextFieldStyle())
        }.frame(maxWidth: .infinity, alignment: .leading).id(title)
    }
}

struct SettingsControlRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 16) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            content.labelsHidden().frame(maxWidth: 260, alignment: .trailing)
        }.frame(minHeight: 32)
    }
}

struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.accessibilityHidden(true).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.frame(minHeight: 32)
    }
}

struct SettingsPageHeader: View {
    var page: MyDockSettingsPage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title).font(DockDesign.pageTitle)
            Text(page.designDescription).font(DockDesign.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }
}

struct SettingsSidebarLabel: View {
    var page: MyDockSettingsPage
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 24, height: 24)
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

extension WidgetCategory {
    var displayColor: Color { switch self { case .productivity: .orange; case .system: .teal; case .time: .orange; case .personal: .pink; case .business: .green; case .ai: .purple } }
    var symbol: String { switch self { case .productivity: "square.grid.2x2"; case .system: "desktopcomputer"; case .time: "clock"; case .personal: "person.crop.circle"; case .business: "chart.bar"; case .ai: "sparkles" } }
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
