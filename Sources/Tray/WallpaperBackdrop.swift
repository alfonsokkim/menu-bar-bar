import AppKit
import SwiftUI
import TrayCore

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

    /// Fullscreen spaces use the Dock's backdrop instead of desktop wallpaper.
    /// Desktop icons, menu material and application windows stay excluded.
    static func windowID(in windows: [[String: Any]], display: CGRect) -> CGWindowID? {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let candidates = windows.filter { info in
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.contains(display)
        }
        let fullscreen = candidates.first {
            ($0[kCGWindowLayer as String] as? Int) == desktop + 1 &&
            ($0[kCGWindowOwnerName as String] as? String) == "Dock" &&
            ($0[kCGWindowName as String] as? String) == "Fullscreen Backdrop"
        }
        let wallpaper = candidates.first {
            guard let layer = $0[kCGWindowLayer as String] as? Int else { return false }
            return (desktop - 1...desktop).contains(layer)
        }
        return (fullscreen ?? wallpaper)?[kCGWindowNumber as String] as? CGWindowID
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
    var joinHeight: CGFloat = 0

    func makeNSView(context: Context) -> WallpaperSurfaceView { WallpaperSurfaceView() }
    func updateNSView(_ view: WallpaperSurfaceView, context: Context) {
        guard view.snapshot?.image !== snapshot?.image || view.snapshot?.frame != snapshot?.frame ||
              view.joinHeight != joinHeight else { return }
        view.snapshot = snapshot
        view.joinHeight = joinHeight
        view.needsDisplay = true
    }
}

final class WallpaperSurfaceView: NSView {
    var snapshot: WallpaperSnapshot?
    var joinHeight: CGFloat = 0
    private struct JoinMask {
        let size: CGSize
        let joinHeight: CGFloat
        let scale: CGFloat
        let image: CGImage
    }
    private var joinMask: JoinMask?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // If capture is unavailable, keep applications behind the shelf hidden.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let snapshot, let window {
            let location = window.convertToScreen(convert(bounds, to: nil))
            let destination = snapshot.frame.offsetBy(dx: -location.minX, dy: -location.minY)
            context.interpolationQuality = .none
            context.draw(snapshot.image, in: destination)
        }
        // Fade only the part above the shelf body. The body keeps the exact
        // wallpaper pixels, while native status windows remain above this panel.
        guard joinHeight > 0 else { return }
        let scale = max(1, hypot(context.ctm.c, context.ctm.d))
        guard let mask = opacityMask(scale: scale) else {
            context.clear(CGRect(x: bounds.minX, y: bounds.maxY - joinHeight,
                                 width: bounds.width, height: joinHeight))
            return
        }
        context.saveGState()
        context.setBlendMode(.destinationIn)
        context.interpolationQuality = .none
        context.draw(mask, in: bounds)
        context.restoreGState()
    }

    private func opacityMask(scale: CGFloat) -> CGImage? {
        if let joinMask, joinMask.size == bounds.size,
           joinMask.joinHeight == joinHeight, joinMask.scale == scale { return joinMask.image }
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * height)
        for y in 0..<min(height, Int(ceil(joinHeight * scale))) {
            for x in 0..<width {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let alpha = ShelfSurface.joinOpacity(at: point, width: bounds.width, joinHeight: joinHeight)
                let value = UInt8((alpha * 255).rounded())
                let offset = y * bitmap.bytesPerRow + x * 4
                for channel in 0..<4 { pixels[offset + channel] = value }
            }
        }
        guard let image = bitmap.makeImage() else { return nil }
        joinMask = JoinMask(size: bounds.size, joinHeight: joinHeight, scale: scale, image: image)
        return image
    }
}
