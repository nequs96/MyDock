#if DEBUG
import SwiftUI

/// Development-only specimen sheets for the redesign vocabulary, exported by
/// `MYDOCK_REDESIGN_QA=1`. Every sample uses fixed fixture text; nothing reads user data.
struct DesignSystemGallery: View {
    enum Component: String, CaseIterable {
        case glass, module, grouped, pill, pager, swatch, sheet
        var renderSize: NSSize {
            switch self {
            case .glass: NSSize(width: 640, height: 220)
            case .module: NSSize(width: 640, height: 260)
            case .grouped: NSSize(width: 560, height: 520)
            case .pill: NSSize(width: 520, height: 180)
            case .pager: NSSize(width: 520, height: 300)
            case .swatch: NSSize(width: 720, height: 190)
            case .sheet: NSSize(width: 560, height: 720)
            }
        }
    }

    var component: Component

    var body: some View {
        Group {
            switch component {
            case .glass: GlassSpecimen()
            case .module: ModuleSpecimen()
            case .grouped: GroupedSpecimen().padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(DockDesign.page)
            case .pill: PillSpecimen()
            case .pager: PagerSpecimen(selection: .standard).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(DockDesign.page)
            case .swatch: SwatchSpecimen().frame(maxWidth: .infinity, maxHeight: .infinity).background(DockDesign.page)
            case .sheet: SheetSpecimen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DockDesign.page)
    }
}

/// A wallpaper with enough structure that glass, blur and edges are visible.
private struct SpecimenWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Stripes sit in an overlay so the wallpaper never widens its container.
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.10, green: 0.17, blue: 0.32), Color(red: 0.33, green: 0.20, blue: 0.27)]
                       : [Color(red: 0.47, green: 0.65, blue: 0.90), Color(red: 0.95, green: 0.71, blue: 0.58)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay {
            HStack(spacing: 46) {
                ForEach(0..<14, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.16)).frame(width: 30).rotationEffect(.degrees(24))
                }
            }
            .frame(width: 0)
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct SpecimenCaption: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

private struct GlassSpecimen: View {
    var body: some View {
        ZStack {
            SpecimenWallpaper()
            HStack(alignment: .top, spacing: 28) {
                sample("Regular") {
                    Image(systemName: "sun.max.fill").font(.system(size: 22, weight: .semibold))
                        .frame(width: 96, height: 96)
                        .dockGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                sample("Clear") {
                    Image(systemName: "moon.fill").font(.system(size: 22, weight: .semibold))
                        .frame(width: 96, height: 96)
                        .dockGlass(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                sample("Tinted") {
                    Image(systemName: "bolt.fill").font(.system(size: 22, weight: .semibold))
                        .frame(width: 96, height: 96)
                        .dockGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: DockDesign.accent)
                }
                sample("Capsule") {
                    Label("Focus", systemImage: "moon.fill").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 36)
                        .dockGlass(.regular, in: Capsule(), interactive: true)
                        .frame(height: 96)
                }
            }
        }
    }
    private func sample<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
            SpecimenCaption(text: title)
        }
    }
}

private struct ModuleSpecimen: View {
    private let dockRadius: CGFloat = 24
    private let dockPadding: CGFloat = 10
    var body: some View {
        ZStack {
            SpecimenWallpaper()
            VStack(spacing: 22) {
                // Concentric family: modules inside a Dock share its centre of curvature.
                let radius = DockDesign.Module.radius(dockRadius: dockRadius, dockPadding: dockPadding)
                HStack(spacing: 8) {
                    GlassModule(width: 54, height: 54, radius: radius) {
                        Image(systemName: "bolt.fill").font(.system(size: DockDesign.Module.Glyph.large, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    GlassModule(width: 118, height: 54, radius: radius) {
                        ModuleValueLabel(value: "72%", label: "Battery", size: .large)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DockDesign.Module.insets)
                    }
                    GlassModule(width: 118, height: 54, radius: radius) {
                        ModuleValueLabel(value: "21°", label: "Cupertino", symbol: "sun.max.fill", size: .medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DockDesign.Module.insets)
                    }
                    GlassModule(width: 182, height: 54, radius: radius, tint: DockDesign.accent) {
                        HStack(spacing: 10) {
                            ModuleValueLabel(value: "09:41", label: "Next alarm", size: .large)
                            Spacer(minLength: 0)
                            Image(systemName: "alarm.fill").font(.system(size: DockDesign.Module.Glyph.medium, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(DockDesign.Module.insets)
                    }
                }
                .padding(dockPadding)
                .dockGlass(.clear, in: RoundedRectangle(cornerRadius: dockRadius, style: .continuous))
                HStack(spacing: 18) {
                    ForEach(DockDesign.Module.ValueSize.allCases, id: \.self) { size in
                        ModuleValueLabel(value: "1,284", label: size == .large ? "Large 22" : size == .medium ? "Medium 18" : "Small 13", size: size)
                    }
                    Text("radius \(Int(DockDesign.Module.radius(dockRadius: dockRadius, dockPadding: dockPadding))) = \(Int(dockRadius)) − \(Int(dockPadding))")
                        .font(DockDesign.Module.label).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .dockGlass(.regular, in: Capsule())
            }
        }
    }
}

private struct GroupedSpecimen: View {
    @State private var showsLabel = true
    @State private var tinted = false
    @State private var size = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupedSection("Widget", footer: "Changes apply to this widget only.") {
                GroupedRow("Show label", symbol: "textformat", color: .blue, isOn: $showsLabel)
                GroupedRow("Glass tint", subtitle: "Use the profile colour behind this widget.", symbol: "drop.fill", color: .purple, isOn: $tinted)
                GroupedRow("Accent", symbol: "paintpalette.fill", color: .orange, value: "Automatic", chevron: true) {}
                GroupedRow("Refresh", symbol: "arrow.clockwise", color: .green, value: "Every 15 min")
                GroupedRow("Size", symbol: "square.resize", color: .gray) {
                    Picker("Size", selection: $size) {
                        Text("Small").tag(0); Text("Standard").tag(1); Text("Wide").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
            GroupedSection {
                GroupedRow("Duplicate Widget", role: .button) {}
                GroupedRow("Remove Widget", role: .destructive) {}
            }
        }
    }
}

private struct PillSpecimen: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                PillButton("Add Widget", systemImage: "plus") {}
                PillButton("Add Widget", systemImage: "plus") {}.disabled(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DockDesign.page)
            PillButton("Add Widget", systemImage: "plus") {}
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SpecimenWallpaper())
        }
    }
}

enum SpecimenSize: String, CaseIterable, Hashable {
    case small = "Small", standard = "Standard", wide = "Wide", large = "Large"
    var width: CGFloat { switch self { case .small: 54; case .standard: 118; case .wide: 182; case .large: 246 } }
}

private struct PagerSpecimen: View {
    @State var selection: SpecimenSize
    var body: some View {
        SizePager(SpecimenSize.allCases, selection: $selection, caption: \.rawValue) { size in
            ZStack {
                SwatchWallpaper().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                GlassModule(width: size.width * 1.4, height: 54 * 1.4, radius: 20, hoverEffect: false) {
                    if size == .small {
                        Image(systemName: "sun.max.fill").font(.system(size: 26, weight: .semibold))
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.max.fill").font(.system(size: 26, weight: .semibold)).symbolRenderingMode(.multicolor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("21°").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                                Text("Cupertino").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .frame(height: 170)
            .padding(.horizontal, 4)
        }
    }
}

private struct SwatchSpecimen: View {
    var body: some View {
        HStack(spacing: 18) {
            StyleSwatch("Clear", look: DockSwatchLook(surface: .clearGlass, showsEdge: false, moduleSurface: .plain), isSelected: false) {}
            StyleSwatch("Glass", look: DockSwatchLook(surface: .glass, moduleSurface: .glass), isSelected: true) {}
            StyleSwatch("Frosted", look: DockSwatchLook(surface: .frosted), isSelected: false) {}
            StyleSwatch("Solid", look: DockSwatchLook(surface: .solid), isSelected: false) {}
            StyleSwatch("Midnight", look: DockSwatchLook(surface: .midnight, moduleSurface: .glass), isSelected: false) {}
        }
    }
}

/// The components together, roughly as the widget detail sheet will use them.
private struct SheetSpecimen: View {
    @State private var showsLabel = true
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Weather").font(.system(size: 22, weight: .semibold))
                Text("Current conditions and the next few hours.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            PagerSpecimen(selection: .standard)
            PillButton("Add Widget", systemImage: "plus") {}
            GroupedSection("Options") {
                GroupedRow("Location", symbol: "location.fill", color: .blue, value: "Current Location", chevron: true) {}
                GroupedRow("Show label", symbol: "textformat", color: .gray, isOn: $showsLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DockDesign.page)
    }
}
#endif
