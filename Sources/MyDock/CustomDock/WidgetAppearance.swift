import AppKit
import SwiftUI

enum WidgetDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let inset = Color.primary.opacity(0.035)
}

struct WidgetEmblem: View {
    var kind: String
    var style: WidgetIconStyle = .tinted
    var size: CGFloat = 28
    var body: some View { WidgetIcon(kind: kind, size: size, appearance: .init(legacy: style)) }
}

/// Compatibility for icon-only actions. Data widgets never use this to switch layout.
struct WidgetIconTile: View {
    var item: DockItem
    var style: WidgetIconStyle
    var width: CGFloat = 54
    var body: some View {
        HStack(spacing: 7) {
            WidgetIcon(kind: item.widgetKind ?? item.title, size: 28, appearance: .init(legacy: style))
            if width > 54 { Text(item.displayName).font(.system(size: 10, weight: .medium)).lineLimit(2) }
        }.frame(width: width, height: 54)
    }
}

struct WidgetAppearanceControls: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var layout: WidgetLayout { WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration, compactDefault: store.effectiveSettings(profileID: profileID).customDockWidgetStyle == .compact) }
    private var previewSettings: AppSettings {
        var settings = store.effectiveSettings(profileID: profileID)
        settings.customDockPosition = .bottom
        return settings
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Dock preview")
                WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: previewSettings)
                    .allowsHitTesting(false)
                if store.effectiveSettings(profileID: profileID).customDockPosition != .bottom {
                    Text("Horizontal layout shown. Side Docks use a narrow presentation.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Layout")
                ForEach(WidgetPresentationCatalog.options(for: kind)) { option in
                    Button {
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.widgetLayout = option.layout }
                    } label: {
                        HStack(spacing: 12) {
                            WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: previewSettings, layoutOverride: option.layout)
                                .allowsHitTesting(false).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title).font(.system(size: 12, weight: .medium))
                                Text(option.detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: layout == option.layout ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(layout == option.layout ? DockDesign.accent : .secondary).font(.system(size: 15))
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(option.title) layout")
                        .accessibilityValue("\(Int(option.width)) points wide")
                        .accessibilityAddTraits(layout == option.layout ? .isSelected : [])
                }
            }
            if kind != "Sticky Note" && kind != "Time Progress" {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Icon")
                    HStack(spacing: 14) {
                        ForEach(WidgetIconAppearance.allCases) { appearance in
                            Button {
                                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.iconAppearance = appearance }
                            } label: {
                                VStack(spacing: 4) {
                                    WidgetIcon(kind: kind, symbol: kind == "AI Activity" ? (configuration.aiActivityProvider == .codex ? "terminal" : "sparkle") : nil, size: 28, appearance: appearance)
                                        .frame(width: 44, height: 40)
                                        .background(configuration.iconAppearance == appearance ? DockDesign.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(configuration.iconAppearance == appearance ? DockDesign.accent.opacity(0.55) : .clear, lineWidth: 1))
                                    Text(appearance.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("\(appearance.title) icon")
                                .accessibilityAddTraits(configuration.iconAppearance == appearance ? .isSelected : [])
                        }
                    }
                }
            }
            if kind == "AI Activity" {
                SettingsControlRow(title: "Secondary metric") {
                    Picker("Secondary metric", selection: Binding(get: { configuration.aiActivitySecondaryMetric }, set: { value in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.aiActivitySecondaryMetric = value }
                    })) { ForEach(AIActivitySecondaryMetric.allCases) { Text($0.title).tag($0) } }
                }
            }
            if kind == "System Activity" {
                SettingsControlRow(title: "Trend secondary") {
                    Picker("Trend secondary", selection: Binding(get: { configuration.systemSecondaryMetric }, set: { value in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemSecondaryMetric = value }
                    })) { ForEach(SystemSecondaryMetric.allCases) { Text($0.title).tag($0) } }
                }
            }
        }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
}

struct WidgetSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DockDesign.hairline, lineWidth: 0.5))
    }
}
