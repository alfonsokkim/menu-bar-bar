import AppKit
import SwiftUI

/// Keep the menu material aligned horizontally while the shelf changes width.
/// Reflect its vertical shading below the join instead of stretching one row.
struct ScreenAlignedMenuSurface: NSViewRepresentable, Animatable {
    let image: NSImage
    let sampleFrame: CGRect
    let barWindowID: CGWindowID?
    var reveal: CGFloat
    let originX: CGFloat
    let rowHeight: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    func makeNSView(context: Context) -> MenuSurfaceView { MenuSurfaceView() }
    func updateNSView(_ view: MenuSurfaceView, context: Context) {
        view.update(image: image, sampleFrame: sampleFrame, barWindowID: barWindowID,
                    reveal: reveal, originX: originX, rowHeight: rowHeight, reduceMotion: reduceMotion)
    }
}

final class MenuSurfaceView: NSView {
    private var image: NSImage?
    private var row: CGImage?
    private var sampleFrame = CGRect.zero
    private var barWindowID: CGWindowID?
    private var reveal: CGFloat = 0
    private var originX: CGFloat = 0
    private var rowHeight: CGFloat = 0
    private var reduceMotion = false

    func update(image: NSImage, sampleFrame: CGRect, barWindowID: CGWindowID?,
                reveal: CGFloat, originX: CGFloat, rowHeight: CGFloat, reduceMotion: Bool) {
        if self.image !== image {
            self.image = image
            row = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(MenuMaterialBlend.interiorRow)
        }
        self.sampleFrame = sampleFrame
        self.barWindowID = barWindowID
        self.reveal = reveal
        self.originX = originX
        self.rowHeight = rowHeight
        self.reduceMotion = reduceMotion
        needsDisplay = true
        updateBridge()
    }

    private func updateBridge() {
        guard let panel = window as? ShelfPanel else { return }
        guard panel.isVisible, reveal > 0, let row, let barWindowID else {
            panel.materialBridge.orderOut(nil)
            return
        }
        let screenFrame = panel.convertToScreen(convert(bounds, to: nil))
        let frame = CGRect(x: screenFrame.minX, y: sampleFrame.maxY,
                           width: screenFrame.width, height: rowHeight / 2)
        panel.materialBridge.placementDidChange = { [weak self] in self?.needsDisplay = true }
        panel.materialBridge.update(frame: frame, row: row, barWindowID: barWindowID, sampleFrame: sampleFrame,
                                    reveal: reveal, originX: originX, rowHeight: rowHeight, reduceMotion: reduceMotion)
    }

    override func layout() {
        super.layout()
        updateBridge()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBridge()
    }
    private var observations: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (window as? ShelfPanel)?.materialBridge.orderOut(nil)
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations = []
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.needsDisplay = true
                    self?.updateBridge()
                }
            })
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let window else { return }
        let screenFrame = window.convertToScreen(convert(bounds, to: nil))
        guard let context = NSGraphicsContext.current?.cgContext,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .low
        context.setBlendMode(.copy)
        // AppKit's origin is at the bottom. Reflect the captured material so
        // its bottom edge meets the native bar and its texture stays varied.
        context.saveGState()
        context.translateBy(x: 0, y: bounds.minY + bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: sampleFrame.minX - screenFrame.minX, y: bounds.minY,
                                         width: sampleFrame.width, height: bounds.height))
        context.restoreGState()
        if let row, (window as? ShelfPanel)?.materialBridge.isReady == true {
            MenuMaterialBlend.draw(row: row, in: context, bounds: bounds,
                                   sampleX: sampleFrame.minX - screenFrame.minX,
                                   sampleWidth: sampleFrame.width, fadeUpward: false)
        }
    }
}
