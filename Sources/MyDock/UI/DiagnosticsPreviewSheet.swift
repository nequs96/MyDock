import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A reviewed report is a value, never a request to regenerate diagnostics at save time.
struct DiagnosticsPreviewPayload: Identifiable {
    let id = UUID()
    let data: Data

    var text: String { String(decoding: data, as: UTF8.self) }

    @discardableResult
    func save(to url: URL?, write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws -> Bool {
        guard let url else { return false }
        try write(data, url)
        return true
    }
}

struct DiagnosticsPreviewSheet: View {
    let payload: DiagnosticsPreviewPayload
    let cancel: () -> Void
    let saved: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DockSheetHeader(title: "Review Diagnostics",
                            subtitle: "Includes app/build versions, item counts, settings and recent event codes. Excludes Dock names, file paths, widget content and credentials. Nothing is uploaded. Save writes exactly the report shown below.")
            ScrollView {
                Text(payload.text).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(minHeight: 240).background(DockDesign.input, in: RoundedRectangle(cornerRadius: DockDesign.Radius.input))
            if let errorMessage { Text(errorMessage).font(DockDesign.caption).foregroundStyle(DockDesign.Status.warning).textSelection(.enabled) }
            HStack {
                Text("\(payload.data.count.formatted()) bytes").font(DockDesign.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save Reviewed Report…", action: save).keyboardShortcut(.defaultAction)
                    .buttonStyle(DockButtonStyle(primary: true))
            }
        }.padding(24).frame(width: 620, height: 540).buttonStyle(DockButtonStyle())
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyDock-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return }
        do {
            if try payload.save(to: panel.url) { saved() }
        } catch {
            errorMessage = "Could not save this report. You can retry with the same reviewed contents. " + error.localizedDescription
        }
    }
}
