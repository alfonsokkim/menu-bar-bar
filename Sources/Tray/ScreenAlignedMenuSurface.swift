import AppKit
import SwiftUI

/// Keep each sampled menu-bar pixel above the same desktop coordinate while
/// the shelf changes width. Only crop the strip; never stretch it horizontally.
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
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: CGRect(x: sampleFrame.minX - screenFrame.minX, y: bounds.minY,
                              width: sampleFrame.width, height: bounds.height),
                   from: .zero, operation: .copy, fraction: 1)
    }
}
