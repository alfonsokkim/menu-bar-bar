import AppKit
import SwiftUI

struct WallpaperSnapshot {
    let image: CGImage
    let frame: CGRect
}

enum WallpaperBackdrop {
    private typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let capture: Capture? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: Capture.self)
    }()

    /// Select only the wallpaper plane. Desktop icons, backstops, menu material,
    /// and normal application windows must never become the shelf background.
    static func windowID(in windows: [[String: Any]], display: CGRect) -> CGWindowID? {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        return windows.first { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  (desktop - 1...desktop).contains(layer),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.contains(display)
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    static func quartzFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func snapshot(for shelf: CGRect, screen: NSScreen) -> WallpaperSnapshot? {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let display = quartzFrame(screen.frame, primaryTop: primaryTop)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let id = windowID(in: windows, display: display) else { return nil }
        // A narrow full-width strip covers horizontal shelf resize animations
        // without scaling or moving the wallpaper within the shape.
        let frame = CGRect(x: screen.frame.minX, y: shelf.minY, width: screen.frame.width, height: shelf.height)
        guard let image = capture?(quartzFrame(frame, primaryTop: primaryTop),
                                   CGWindowListOption.optionIncludingWindow.rawValue, id,
                                   CGWindowImageOption.bestResolution.rawValue)?.takeRetainedValue(),
              StatusIconCache.hasVisiblePixels(image) else { return nil }
        return WallpaperSnapshot(image: image, frame: frame)
    }
}

struct WallpaperSurface: NSViewRepresentable {
    let snapshot: WallpaperSnapshot?

    func makeNSView(context: Context) -> WallpaperSurfaceView { WallpaperSurfaceView() }
    func updateNSView(_ view: WallpaperSurfaceView, context: Context) {
        view.snapshot = snapshot
        view.needsDisplay = true
    }
}

final class WallpaperSurfaceView: NSView {
    var snapshot: WallpaperSnapshot?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // If capture is unavailable, keep applications behind the shelf hidden.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let snapshot, let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let location = window.convertToScreen(convert(bounds, to: nil))
        let destination = snapshot.frame.offsetBy(dx: -location.minX, dy: -location.minY)
        context.interpolationQuality = .none
        context.draw(snapshot.image, in: destination)
    }
}
