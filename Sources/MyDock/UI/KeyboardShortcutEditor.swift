import AppKit
import SwiftUI

struct KeyboardShortcutEditor: View {
    var profileID: UUID
    var profileName: String
    @ObservedObject var bindings: DockShortcutStore
    @ObservedObject var controller: GlobalShortcutController
    var onClose: () -> Void

    @State private var isRecording = false
    @State private var message: String?

    private var currentShortcut: DockShortcut? { bindings.shortcut(for: profileID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcut").font(.title2.bold())
            Text("Switch to \(profileName) from any app.").foregroundStyle(.secondary)

            HStack {
                Text(currentShortcut?.displayString ?? "No shortcut")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospaced())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                if currentShortcut != nil {
                    Button("Clear") {
                        bindings.remove(for: profileID)
                        message = nil
                    }
                }
            }

            if isRecording {
                ShortcutCaptureView { event in capture(event) }
                    .frame(height: 52)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.5)))
                Text("Press a key with at least two modifiers. Escape or Delete clears the shortcut.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let registrationStatus = controller.statusMessages[profileID] {
                Label(registrationStatus, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button(isRecording ? "Listening…" : "Record Shortcut") { isRecording = true; message = nil }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 430).frame(minHeight: 250)
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            bindings.remove(for: profileID)
            isRecording = false
            message = "Shortcut cleared."
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mask: UInt8 = 0
        if flags.contains(.command) { mask |= DockShortcut.commandMask }
        if flags.contains(.option) { mask |= DockShortcut.optionMask }
        if flags.contains(.control) { mask |= DockShortcut.controlMask }
        if flags.contains(.shift) { mask |= DockShortcut.shiftMask }
        let label = keyLabel(for: event)
        let shortcut = DockShortcut(keyCode: event.keyCode, modifierMask: mask, keyLabel: label)
        guard shortcut.isValid else {
            message = DockShortcutStoreError.requiresTwoModifiers.localizedDescription
            return
        }
        do {
            try bindings.set(shortcut, for: profileID)
            isRecording = false
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func keyLabel(for event: NSEvent) -> String {
        if let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty {
            return characters.uppercased()
        }
        return switch event.keyCode {
        case 36: "Return"
        case 48: "Tab"
        case 49: "Space"
        case 53: "Escape"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "Key \(event.keyCode)"
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    var onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) { onCapture?(event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onCapture?(event)
        return true
    }
}
