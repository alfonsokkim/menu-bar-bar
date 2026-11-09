import AppKit
import SwiftUI

/// Keep the menu material aligned horizontally while the shelf changes width.
/// Reflect its vertical shading below the join instead of stretching one row.
struct ScreenAlignedMenuSurface: NSViewRepresentable {
    let image: NSImage
    let sampleFrame: CGRect

    func makeNSView(context: Context) -> MenuSurfaceView { MenuSurfaceView() }
    func updateNSView(_ view: MenuSurfaceView, context: Context) {
        view.image = image
        view.sampleFrame = sampleFrame
        view.needsDisplay = true
    }
}

final class MenuSurfaceView: NSView {
    var image: NSImage?
    var sampleFrame = CGRect.zero
    private var observations: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations = []
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
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
        context.translateBy(x: 0, y: bounds.minY + bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: sampleFrame.minX - screenFrame.minX, y: bounds.minY,
                                         width: sampleFrame.width, height: bounds.height))
    }
}
