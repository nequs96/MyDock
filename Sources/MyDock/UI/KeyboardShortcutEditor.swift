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
            DockSheetHeader(title: "Keyboard Shortcut", subtitle: "Switch to \(profileName) from any app.")

            HStack {
                Text(currentShortcut?.displayString ?? "No shortcut")
                    .font(.system(size: 20, weight: .medium).monospaced())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DockDesign.input, in: RoundedRectangle(cornerRadius: DockDesign.Radius.input))
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
                    .background(DockDesign.input, in: RoundedRectangle(cornerRadius: DockDesign.Radius.input))
                    .overlay(RoundedRectangle(cornerRadius: DockDesign.Radius.input).stroke(DockDesign.accent))
                Text("Press a key with at least two modifiers. Delete clears it; Escape cancels.")
                    .font(DockDesign.caption).foregroundStyle(.secondary)
            }

            if let registrationStatus = controller.statusMessages[profileID] {
                Label(registrationStatus, systemImage: "exclamationmark.triangle.fill")
                    .font(DockDesign.caption).foregroundStyle(.orange)
            }
            if let message {
                Text(message).font(DockDesign.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if isRecording {
                    Button("Cancel") { isRecording = false; message = nil }
                } else {
                    Button("Done", action: onClose)
                }
                Button(isRecording ? "Listening…" : "Record Shortcut") { isRecording = true; message = nil }
                    .buttonStyle(DockButtonStyle(primary: true))
            }
        }
        .padding(24)
        .frame(width: 430).frame(minHeight: 250).background(DockDesign.page).buttonStyle(DockButtonStyle())
    }

    private func capture(_ event: NSEvent) {
        // Escape cancels recording and keeps the current shortcut; Delete clears it.
        if event.keyCode == 53 {
            isRecording = false
            message = nil
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
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
        let label = DockShortcut.label(keyCode: event.keyCode, characters: event.characters(byApplyingModifiers: []))
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

}

extension DockShortcut {
    /// The stored label for a recorded key. Named keys come from the key code, since AppKit
    /// reports arrows, function keys and the like as private-use characters; printable keys
    /// use their unmodified character, so Shift-1 reads "1", not "!".
    static func label(keyCode: UInt16, characters: String?) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty,
           !characters.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }) {
            return characters.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let namedKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 53: "Escape", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15"
    ]
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
