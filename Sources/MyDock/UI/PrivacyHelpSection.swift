import SwiftUI

/// Short privacy and limitations help shown on the General and Integrations pages.
struct PrivacyHelpSection: View {
    var body: some View {
        DockSettingSection(title: PrivacyHelpCopy.privacyTitle) {
            DisclosureGroup("What is stored and what is not") {
                bullets(PrivacyHelpCopy.privacyPoints).padding(.top, 8)
            }
            DisclosureGroup(PrivacyHelpCopy.limitationsTitle) {
                bullets(PrivacyHelpCopy.limitationPoints).padding(.top, 8)
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
