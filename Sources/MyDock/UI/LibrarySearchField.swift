import AppKit
import SwiftUI

/// AppKit routes arrow and Return commands from the field editor to the library
/// without taking focus away from search or swallowing normal text editing.
struct LibrarySearchField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    let move: (Int) -> Void
    let choose: () -> Void
    let cancel: () -> Void
    var compact = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = compact ? .default : .none
        field.font = .systemFont(ofSize: compact ? 13 : 16)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        DispatchQueue.main.async { [weak field] in
            if let field { field.window?.makeFirstResponder(field) }
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LibrarySearchField
        init(_ parent: LibrarySearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.choose()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }
}
