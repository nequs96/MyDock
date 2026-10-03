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
    @Environment(\.dockWidgetContentWidth) private var width

    var body: some View {
        let label = status.errorMessage != nil ? "Unavailable" : status.itemCount == 0 ? "Empty" : "\(status.itemCount)"
        Group {
            if width > 54 {
                HStack(spacing: 7) {
                    Image(systemName: status.errorMessage != nil ? "exclamationmark.triangle" : status.itemCount == 0 ? "trash" : "trash.fill")
                        .font(.system(size: 21, weight: .regular))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trash").font(.system(size: 10, weight: .medium))
                        Text(label).font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit()).foregroundStyle(.secondary)
                    }.lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: status.errorMessage != nil ? "exclamationmark.triangle" : status.itemCount == 0 ? "trash" : "trash.fill")
                        .font(.system(size: 23, weight: .regular))
                    Text(label)
                        .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .frame(width: width, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trash")
        .accessibilityValue(status.errorMessage ?? (status.itemCount == 0 ? "Empty" : "\(status.itemCount) items"))
        .help(status.errorMessage ?? (status.itemCount == 0 ? "Trash is empty" : "\(status.itemCount) items in Trash"))
    }
}

private struct TrashPopoutWidgetView: View {
    @ObservedObject private var status = TrashStatus.shared
    @State private var confirmingEmpty = false
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: status.errorMessage != nil ? "exclamationmark.triangle" : status.itemCount == 0 ? "trash" : "trash.fill")
                    .font(.system(size: 36)).foregroundColor(status.itemCount == 0 ? Color.secondary : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.errorMessage != nil ? "Trash Unavailable" : status.itemCount == 0 ? "Trash is Empty" : "\(status.itemCount) Items")
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
                    .buttonStyle(DockButtonStyle())
                Spacer()
                Button("Empty Trash…", role: .destructive) { confirmingEmpty = true }
                    .buttonStyle(DockButtonStyle(primary: true))
                    .disabled(status.itemCount == 0 || status.errorMessage != nil)
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
        Task { @MainActor in
            do { try await TrashActions.emptyTrash(); status.refresh() }
            catch { actionError = error.localizedDescription }
        }
    }
}
