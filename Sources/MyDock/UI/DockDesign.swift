import SwiftUI

enum DockDesign {
    static let accent = Color(red: 0.22, green: 0.43, blue: 0.83)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.09)
}

struct DockScreenHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(DockDesign.accent)
            Text(title)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DockSettingSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DockDesign.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DockDesign.hairline))
    }
}

extension DockProfileColor {
    var displayColor: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }
}

extension WidgetCategory {
    var displayColor: Color {
        switch self {
        case .productivity: .orange
        case .system: .teal
        case .time: .orange
        case .personal: .pink
        case .business: .green
        case .ai: .purple
        }
    }
}
