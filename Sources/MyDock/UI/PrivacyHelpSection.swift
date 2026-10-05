import SwiftUI

/// Short privacy and limitations help shown on the General and Integrations pages.
struct PrivacyHelpSection: View {
    @State private var privacyExpanded = false
    @State private var limitationsExpanded = false
    var body: some View {
        GroupedSection(PrivacyHelpCopy.privacyTitle) {
            SettingsExpansionRow(title: "What is stored and what is not", isExpanded: $privacyExpanded) {
                bullets(PrivacyHelpCopy.privacyPoints)
            }
            SettingsExpansionRow(title: PrivacyHelpCopy.limitationsTitle, isExpanded: $limitationsExpanded) {
                bullets(PrivacyHelpCopy.limitationPoints)
            }
        }
    }

    private func bullets(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(points, id: \.self) { point in
                Text(point).font(DockDesign.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
