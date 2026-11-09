import AppKit
import SwiftUI
import TrayCore

/// Normal clicks reach the SwiftUI button. Command-drags use an AppKit drag
/// session so the icon follows the pointer across the menu-bar boundary.
struct CommandDragSource: NSViewRepresentable {
    let item: MenuItem
    let controller: TrayController

    func makeNSView(context: Context) -> CommandDragView { CommandDragView() }
    func updateNSView(_ view: CommandDragView, context: Context) {
        view.item = item
        view.controller = controller
    }
}

final class CommandDragView: NSView, NSDraggingSource {
    var item: MenuItem?
    weak var controller: TrayController?
    private var initialEvent: NSEvent?
    private var sessionItemID: UInt32?
    private var dragImage = StatusDragImage()

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSEvent.modifierFlags.contains(.command), controller?.movingItemID == nil else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { initialEvent = event }
    override func mouseUp(with event: NSEvent) { initialEvent = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let initialEvent, let item, let controller,
              hypot(event.locationInWindow.x - initialEvent.locationInWindow.x,
                    event.locationInWindow.y - initialEvent.locationInWindow.y) >= 4,
              controller.beginShelfDrag(item.id) else { return }
        self.initialEvent = nil
        sessionItemID = item.id
        dragImage = StatusDragImage()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(item.id), forType: NSPasteboard.PasteboardType("com.alfonsokim.tray.status-item"))
        let drag = NSDraggingItem(pasteboardWriter: pasteboardItem)
        drag.setDraggingFrame(bounds, contents: item.image ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil))
        let session = beginDraggingSession(with: [drag], event: event, source: self)
        // The menu bar does not accept pasteboard drops. The controller commits
        // only a release in the shelf or a valid native menu-bar slot.
        session.animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        controller?.updateShelfDrag(at: session.draggingLocation, imageFrame: imageFrame(in: session))
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let id = sessionItemID else { return }
        sessionItemID = nil
        let imageFrame = imageFrame(in: session)
        dragImage = StatusDragImage()
        controller?.finishShelfDrag(id, at: session.draggingLocation, imageFrame: imageFrame,
                                    mouseReleased: NSEvent.pressedMouseButtons & 1 == 0)
    }

    private func imageFrame(in session: NSDraggingSession) -> CGRect? {
        var frame: CGRect?
        session.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, stop in
            frame = item.draggingFrame
            stop.pointee = true
        }
        if let frame { dragImage.observe(frame: frame, pointer: session.draggingLocation) }
        return dragImage.frame(at: session.draggingLocation)
    }

    func dragImageFrame(at point: CGPoint) -> CGRect? { dragImage.frame(at: point) }
}

final class StatusDragMonitor {
    enum Phase { case began, moved, ended, cancelled }
    var handle: ((Phase, CGPoint, Bool) -> Void)?
    private var global: Any?
    private var local: Any?

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receive(event)
            return event
        }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
    private func receive(_ event: NSEvent) {
        let phase: Phase
        switch event.type {
        case .leftMouseDown: phase = .began
        case .leftMouseDragged: phase = .moved
        case .leftMouseUp: phase = .ended
        default: return
        }
        // Never bridge keyboard events. Only the three mouse types above
        // belong to this observer, and generated move events are ignored.
        guard let mouseEvent = event.cgEvent else { return }
        if StatusItemMover.isMoveEvent(mouseEvent.getIntegerValueField(.eventSourceUserData)) { return }
        let point = CGPoint(x: mouseEvent.location.x,
                            y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouseEvent.location.y)
        handle?(phase, point, event.modifierFlags.contains(.command))
    }
}

/// Accept only the current shelf's own drag. The source commits the shelf
/// order once, after AppKit ends the drag session.
final class ShelfHostingView: NSHostingView<ShelfView> {
    private weak var controller: TrayController?

    init(controller: TrayController) {
        self.controller = controller
        super.init(rootView: ShelfView(controller: controller))
        registerForDraggedTypes([NSPasteboard.PasteboardType("com.alfonsokim.tray.status-item")])
    }
    required init(rootView: ShelfView) {
        super.init(rootView: rootView)
    }
    required init?(coder: NSCoder) { nil }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? CommandDragView,
              let controller, source.controller === controller,
              source.item?.id == controller.shelfDraggedItemID,
              let window else { return false }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        return controller.updateShelfDrag(at: point, imageFrame: source.dragImageFrame(at: point))
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .move : [] }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .move : [] }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepts(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { controller?.shelfDropIndicatorX = nil }
}
