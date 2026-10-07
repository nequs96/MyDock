import AppKit
import UniformTypeIdentifiers

/// Runs a modal prompt from the Dock. The Dock is a non-activating panel in an accessory app, so
/// MyDock activates first: the alert opens in front and its text field receives typing instead of
/// the app that was frontmost.
@MainActor
enum DockModal {
    @discardableResult
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        activateMyDock()
        if let field = alert.accessoryView { alert.window.initialFirstResponder = field }
        return alert.runModal()
    }

    static func run(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
        activateMyDock()
        return panel.runModal()
    }

    private static func activateMyDock() {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// The Dock's add, rename and customize prompts. Each returns what the person entered, or nil when
/// they cancelled; the Dock view applies the result to the store.
@MainActor
enum DockItemPrompts {
    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Application to Custom Dock"
        panel.prompt = "Add Application"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard DockModal.run(panel) == .OK else { return nil }
        return panel.url
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Folder to Custom Dock"
        panel.prompt = "Add Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard DockModal.run(panel) == .OK else { return nil }
        return panel.url
    }

    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add File to Custom Dock"
        panel.prompt = "Add File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard DockModal.run(panel) == .OK else { return nil }
        return panel.url
    }

    /// A validated http(s) address; an invalid one shows why and returns nil.
    static func webLink() -> URL? {
        let field = textField(width: 300)
        field.placeholderString = "https://example.com"
        guard run("Add a Web Link", "Enter an HTTP or HTTPS address.", field: field, confirm: "Add Link") else { return nil }
        return validatedLink(field.stringValue)
    }

    /// The entered name, trimmed; empty means "use the site's host name".
    static func linkName(for item: DockItem) -> String? {
        let field = textField(width: 300)
        field.stringValue = item.title
        field.placeholderString = item.url?.host
        guard run("Rename Link", "Choose a name shown in this Dock. Clear the field to use the site's host name.",
                  field: field, confirm: "Save Name") else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A validated http(s) address; an invalid one shows why and returns nil.
    static func linkAddress(for item: DockItem) -> URL? {
        let field = textField(width: 320)
        field.stringValue = item.url?.absoluteString ?? "https://"
        guard run("Change Link Address", "Use a valid HTTP or HTTPS address.", field: field, confirm: "Save Address") else { return nil }
        return validatedLink(field.stringValue)
    }

    /// The entered name, trimmed; empty means "use the folder's Finder name".
    static func folderName(for item: DockItem) -> String? {
        let field = textField(width: 300)
        field.stringValue = item.folderCustomName ?? item.title
        field.placeholderString = item.title
        guard run("Customize Folder", "Choose a name shown in this Dock. Clear the field to use the folder’s Finder name.",
                  field: field, confirm: "Save Name") else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One uppercase letter, or empty to remove it.
    static func folderLetter(for item: DockItem) -> String? {
        let field = textField(width: 180)
        field.stringValue = item.folderIconLetter ?? ""
        guard run("Folder Icon Letter", "Enter one optional letter, or clear the field to remove it.",
                  field: field, confirm: "Save Letter") else { return nil }
        return String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    static func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        DockModal.run(alert)
    }

    private static func textField(width: CGFloat) -> NSTextField {
        NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
    }

    private static func run(_ title: String, _ message: String, field: NSTextField, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        return DockModal.run(alert) == .alertFirstButtonReturn
    }

    private static func validatedLink(_ value: String) -> URL? {
        guard let url = DockLinkPolicy.validatedURL(value) else {
            showError("Enter a valid web address", "MyDock accepts HTTP and HTTPS links only.")
            return nil
        }
        return url
    }
}
