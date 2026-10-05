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
    /// Overrides the compact (13 pt) or regular (16 pt) size, e.g. inside a search pill.
    var fontSize: CGFloat? = nil
    /// Takes keyboard focus when it appears. Off when focus is being returned elsewhere,
    /// e.g. to the widget tile a closed detail view came from.
    var focusOnAppear = true
    /// Tab out of the field; return true when the caller moved focus itself.
    var tab: (() -> Bool)? = nil
    /// The user started typing in the field.
    var didBeginEditing: (() -> Void)? = nil
    /// Option-Return: the selected result's secondary action, when it has one.
    var secondary: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = compact ? .default : .none
        field.font = .systemFont(ofSize: fontSize ?? (compact ? 13 : 16))
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        if focusOnAppear {
            DispatchQueue.main.async { [weak field] in
                if let field { field.window?.makeFirstResponder(field) }
            }
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LibrarySearchField
        init(_ parent: LibrarySearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.didBeginEditing?() }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.choose()
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                guard let run = parent.secondary else { return false }
                run()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            case #selector(NSResponder.insertTab(_:)): return parent.tab?() ?? false
            default: return false
            }
            return true
        }
    }
}
