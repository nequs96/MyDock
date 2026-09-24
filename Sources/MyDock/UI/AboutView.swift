import SwiftUI

struct AboutView: View {
    var onReplaySetup: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dock.rectangle").font(.system(size: 46)).foregroundStyle(.tint)
            Text(Product.name).font(.title.bold())
            Text("Your Dock, arranged your way.").foregroundStyle(.secondary)
            Text("Clean-room implementation based on publicly documented Dockset behavior.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let referenceURL = URL(string: "https://dockset.app/manual") {
                Link("Dockset public manual", destination: referenceURL)
            }
            Button("Replay Setup…", action: onReplaySetup)
        }
        .padding(30).frame(width: 380, height: 310)
    }
}
