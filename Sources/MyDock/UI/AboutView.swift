import AppKit
import SwiftUI

struct AboutView: View {
    var onReplaySetup: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "dock.rectangle").font(.system(size: 38, weight: .light))
                        .foregroundStyle(DockDesign.accent)
                }
            }.frame(width: 80, height: 80).accessibilityHidden(true)
            Text(Product.name).font(.system(size: 26, weight: .semibold))
            Text("Your Dock, arranged your way.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(Product.marketingVersion) · macOS 13 or later")
                .font(.caption).foregroundStyle(.tertiary)
            Button("Replay Setup…", action: onReplaySetup).buttonStyle(DockButtonStyle())
        }
        .padding(36).frame(minWidth: 400, minHeight: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DockDesign.page)
        .tint(DockDesign.accent)
    }
}
