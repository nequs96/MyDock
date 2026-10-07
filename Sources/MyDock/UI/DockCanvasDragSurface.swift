import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// A single native drag destination covers the Dock, including the gaps and
/// trailing material. SwiftUI continues to render and expose accessible items.
struct DockCanvasDragSurface: NSViewRepresentable {
    let profileID: UUID
    let items: [DockItem]
    let frames: [UUID: CGRect]
    let selection: Set<UUID>
    let select: (UUID, Bool, Bool) -> Void
    let hover: (UUID?, Bool) -> Void
    let lift: (Set<UUID>) -> Void
    let drop: ([DockDropValue], UUID?) -> Bool

    func makeNSView(context: Context) -> DockCanvasDragView { DockCanvasDragView() }
    func updateNSView(_ view: DockCanvasDragView, context: Context) {
        view.profileID = profileID
        view.items = items
        view.itemFrames = frames
        view.selection = selection
        view.selectItem = select
        view.showInsertion = hover
        view.showLift = lift
        view.applyDrop = drop
    }
}

struct DockCanvasItemFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
final class DockCanvasDragView: NSView {
    var profileID = UUID()
    var items: [DockItem] = []
    var itemFrames: [UUID: CGRect] = [:]
    var selection: Set<UUID> = []
    var selectItem: (UUID, Bool, Bool) -> Void = { _, _, _ in }
    var showInsertion: (UUID?, Bool) -> Void = { _, _ in }
    var showLift: (Set<UUID>) -> Void = { _ in }
    var applyDrop: ([DockDropValue], UUID?) -> Bool = { _, _ in false }
    private var pressedItem: UUID?
    private var pressPoint = CGPoint.zero
    private var pressModifiers: NSEvent.ModifierFlags = []
    private var draggedIDs: Set<UUID> = []
    private var draggedProfileID: UUID?
    private var liftedImage: NSImageView?
    private var imageOffset = CGPoint.zero
    private weak var previousResponder: NSResponder?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([DockCanvasPasteboard.itemsType, .fileURL, .URL])
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true { return nil }
        // Native scrolling and the existing SwiftUI context menus stay in charge.
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .scrollWheel: return nil
        default: return self
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelDrag()
        pressPoint = convert(event.locationInWindow, from: nil)
        pressedItem = items.first(where: { itemFrames[$0.id]?.contains(pressPoint) == true })?.id
        pressModifiers = event.modifierFlags
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var restorePreviousResponder = true
        defer { cancelDrag(restorePreviousResponder: restorePreviousResponder) }
        if !draggedIDs.isEmpty {
            guard bounds.contains(point), draggedProfileID == profileID else { return }
            let payload = DockDragPayload(profileID: profileID, itemIDs: items.filter { draggedIDs.contains($0.id) }.map(\.id))
            if payload.itemIDs.count == 1, let id = payload.itemIDs.first, !selection.contains(id) {
                selectItem(id, false, false)
            }
            // A successful reorder can replace the old tile's native responder.
            // SwiftUI reacquires its current cursor; cancellation restores the old one.
            restorePreviousResponder = !applyDrop([.items(payload)], insertion(at: point, excluding: draggedIDs))
        } else if let id = pressedItem, itemFrames[id]?.contains(point) == true {
            selectItem(id, pressModifiers.contains(.command), pressModifiers.contains(.shift))
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let id = pressedItem, let frame = itemFrames[id] else { return }
        let point = convert(event.locationInWindow, from: nil)
        if draggedIDs.isEmpty {
            guard hypot(point.x - pressPoint.x, point.y - pressPoint.y) >= 4 else { return }
            draggedIDs = selection.contains(id) ? selection : [id]
            draggedProfileID = profileID
            previousResponder = window?.firstResponder
            window?.makeFirstResponder(self)
            if let image = snapshot(of: frame) {
                let lifted = NSImageView(frame: frame)
                lifted.image = image
                lifted.imageScaling = .scaleProportionallyUpOrDown
                lifted.wantsLayer = true
                lifted.layer?.shadowColor = NSColor.black.cgColor
                lifted.layer?.shadowOpacity = 0.2
                lifted.layer?.shadowRadius = 8
                lifted.layer?.shadowOffset = CGSize(width: 0, height: -3)
                addSubview(lifted)
                liftedImage = lifted
                imageOffset = CGPoint(x: pressPoint.x - frame.minX, y: pressPoint.y - frame.minY)
            }
            showLift(draggedIDs)
        }
        autoscroll(with: event)
        liftedImage?.setFrameOrigin(CGPoint(x: point.x - imageOffset.x, y: point.y - imageOffset.y - 3))
        showInsertion(insertion(at: point, excluding: draggedIDs), bounds.contains(point))
    }
    /// Escape cancels a lift here; ⌘. and other window-level cancels arrive as cancelOperation.
    override func cancelOperation(_ sender: Any?) { cancelDrag() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { cancelDrag() } else { super.keyDown(with: event) }
    }
    private func cancelDrag(restorePreviousResponder: Bool = true) {
        if restorePreviousResponder, window?.firstResponder === self { window?.makeFirstResponder(previousResponder) }
        previousResponder = nil
        pressedItem = nil
        draggedIDs = []
        draggedProfileID = nil
        liftedImage?.removeFromSuperview()
        liftedImage = nil
        showLift([])
        showInsertion(nil, false)
    }
    private func insertion(at point: CGPoint, excluding moved: Set<UUID>) -> UUID? {
        items.first(where: { !moved.contains($0.id) && (itemFrames[$0.id]?.midX ?? .greatestFiniteMagnitude) > point.x })?.id
    }

    private func snapshot(of frame: CGRect) -> NSImage? {
        guard let content = window?.contentView else { return nil }
        let region = convert(frame, to: content)
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: region) else { return nil }
        content.cacheDisplay(in: region, to: bitmap)
        let image = NSImage(size: frame.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let values = DockCanvasPasteboard.values(from: sender.draggingPasteboard)
        if values.contains(where: { if case .items(let payload) = $0 { return payload.profileID == profileID }; return false }) { return .move }
        if values.contains(where: { if case .url = $0 { return true }; return false }) { return .copy }
        return []
    }
    private func destination(for sender: NSDraggingInfo) -> UUID? {
        let point = convert(sender.draggingLocation, from: nil)
        let moved = DockCanvasPasteboard.values(from: sender.draggingPasteboard).reduce(into: Set<UUID>()) { ids, value in
            if case .items(let payload) = value, payload.profileID == profileID { ids.formUnion(payload.itemIDs) }
        }
        return insertion(at: point, excluding: moved)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let allowed = operation(for: sender)
        if !allowed.isEmpty { showInsertion(destination(for: sender), true) }
        return allowed
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { showInsertion(nil, false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !operation(for: sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let values = DockCanvasPasteboard.values(from: sender.draggingPasteboard)
        let target = destination(for: sender)
        showInsertion(nil, false)
        return applyDrop(values, target)
    }
}

@MainActor
enum DockCanvasPasteboard {
    static let itemsType = NSPasteboard.PasteboardType(UTType.myDockItems.identifier)
    static func values(from pasteboard: NSPasteboard) -> [DockDropValue] {
        if let data = pasteboard.data(forType: itemsType), data.count <= 256 * 1024,
           let payload = try? JSONDecoder().decode(DockDragPayload.self, from: data) { return [.items(payload)] }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        return urls.prefix(100).map(DockDropValue.url)
    }
}
