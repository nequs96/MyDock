import SwiftUI

struct AboutView: View {
    var onReplaySetup: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(DockDesign.accent.gradient, in: RoundedRectangle(cornerRadius: 21))
            Text(Product.name).font(.system(size: 32, weight: .medium, design: .serif))
            Text("Your Dock, arranged your way.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(Product.marketingVersion) · macOS 13 or later")
                .font(.caption).foregroundStyle(.tertiary)
            Button("Replay setup…", action: onReplaySetup).buttonStyle(.borderedProminent)
        }
        .padding(36).frame(minWidth: 400, minHeight: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DockDesign.page)
        .tint(DockDesign.accent)
    }
}
