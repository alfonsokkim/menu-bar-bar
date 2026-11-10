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
        // Match the native surface at the join, then ease back to the sharp
        // wallpaper. Sampling only its bottom pixel excludes status glyphs.
        var joined = image
        if let bar = MenuBarGeometry.window(in: windows, display: display) {
            let scale = screen.backingScaleFactor
            // WindowServer can return an opaque white image for a sub-point
            // capture. Capture the bar at its native size before cropping.
            if let material = capture?(bar.frame,
                    CGWindowListOption.optionOnScreenBelowWindow.union(.optionIncludingWindow).rawValue,
                    bar.id, CGWindowImageOption.bestResolution.rawValue)?.takeRetainedValue(),
               let edge = nativeEdge(from: material) {
                joined = joinedImage(wallpaper: image, edge: edge, transitionPixels: Int(12 * scale)) ?? image
            }
        }
        return WallpaperSnapshot(image: joined, frame: frame)
    }

    /// WindowServer sometimes returns the entire bar as opaque black. A real
    /// dark bar still contains its menu titles. Never extend an empty capture.
    static func nativeEdge(from material: CGImage) -> CGImage? {
        let width = material.width
        let height = material.height
        let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(material, in: CGRect(x: 0, y: 0, width: width, height: height))
        for offset in stride(from: 0, to: context.bytesPerRow * height, by: 4) {
            if pixels[offset + 3] > 0 && (pixels[offset] > 0 || pixels[offset + 1] > 0 || pixels[offset + 2] > 0) {
                guard let edge = material.cropping(to: CGRect(x: 0, y: height - 1, width: width, height: 1)),
                      StatusIconCache.hasVisiblePixels(edge) else { return nil }
                return edge
            }
        }
        return nil
    }

    /// Carry the native edge's colour correction into the first few wallpaper
    /// rows. Preserve the wallpaper's detail and leave all lower rows untouched.
    static func joinedImage(wallpaper: CGImage, edge: CGImage, transitionPixels: Int) -> CGImage? {
        let width = wallpaper.width
        let height = wallpaper.height
        let rows = min(height, transitionPixels)
        guard rows > 1 else { return wallpaper }
        let space = wallpaper.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: format),
              let sample = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: format),
              let pixels = output.data?.assumingMemoryBound(to: UInt8.self),
              let edgePixels = sample.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        output.draw(wallpaper, in: CGRect(x: 0, y: 0, width: width, height: height))
        sample.interpolationQuality = .none
        sample.draw(edge, in: CGRect(x: 0, y: 0, width: width, height: 1))
        // Save the original top row before modifying it.
        let top = Array(UnsafeBufferPointer(start: pixels, count: width * 4))
        for y in 0..<rows {
            let t = Double(y) / Double(rows - 1)
            let weight = 1 - t * t * (3 - 2 * t)
            for x in 0..<width {
                let column = x * 4
                let offset = y * output.bytesPerRow + column
                for channel in 0..<3 {
                    let alpha = Double(edgePixels[column + 3]) / 255
                    let correction = Double(edgePixels[column + channel]) - Double(top[column + channel]) * alpha
                    let value = Double(pixels[offset + channel]) + correction * weight
                    pixels[offset + channel] = UInt8(clamping: Int(value.rounded()))
                }
            }
        }
        return output.makeImage()
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
