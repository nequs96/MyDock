import SwiftUI

struct TrashWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TrashCompactWidgetView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TrashPopoutWidgetView())
    }
}

private struct TrashCompactWidgetView: View {
    @ObservedObject private var status = TrashStatus.shared

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: status.itemCount == 0 ? "trash" : "trash.fill")
                .font(.system(size: 23, weight: .regular))
            Text(status.itemCount == 0 ? "Empty" : "\(status.itemCount)")
                .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 54, height: 54)
        .help(status.itemCount == 0 ? "Trash is empty" : "\(status.itemCount) items in Trash")
    }
}

private struct TrashPopoutWidgetView: View {
    @ObservedObject private var status = TrashStatus.shared
    @State private var confirmingEmpty = false
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: status.itemCount == 0 ? "trash" : "trash.fill")
                    .font(.system(size: 36)).foregroundColor(status.itemCount == 0 ? Color.secondary : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.itemCount == 0 ? "Trash is Empty" : "\(status.itemCount) Items")
                        .font(.title3.weight(.semibold))
                    Text("Items in your home-folder Trash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let errorMessage = status.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Open Trash", action: TrashActions.openTrash)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Empty Trash…", role: .destructive) { confirmingEmpty = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(status.itemCount == 0)
            }
        }
        .padding(.bottom, 4)
        .frame(width: 300)
        .task { status.refresh() }
        .confirmationDialog("Permanently delete the items in your Trash?", isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive, action: emptyTrash)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. Finder may show its own confirmation before deleting items.")
        }
        .alert("Trash", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func emptyTrash() {
        do {
            try TrashActions.emptyTrash()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                status.refresh()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
