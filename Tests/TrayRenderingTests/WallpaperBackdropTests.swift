import AppKit
import Testing
@testable import Tray

@MainActor @Test func wallpaperSelectionExcludesApplicationsIconsAndOtherDisplays() {
    let desktop = Int(CGWindowLevelForKey(.desktopWindow))
    let display = CGRect(x: 1800, y: -1080, width: 1920, height: 1080)
    func window(_ id: CGWindowID, _ layer: Int, _ frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
    let app = window(1, 0, display)
    let icons = window(2, Int(CGWindowLevelForKey(.desktopIconWindow)), display)
    let backstop = window(3, desktop - 3, display)
    let otherDisplay = window(4, desktop - 1, CGRect(x: 0, y: 0, width: 1800, height: 1169))
    let wallpaper = window(5, desktop - 1, display)
    let unrelated = [app, icons, backstop, otherDisplay]
    #expect(WallpaperBackdrop.windowID(in: unrelated, display: display) == nil)
    #expect(WallpaperBackdrop.windowID(in: unrelated + [wallpaper], display: display) == 5)
    #expect(WallpaperBackdrop.windowID(in: [window(6, desktop, display)], display: display) == 6)
}

@MainActor @Test func wallpaperCoordinatesHandleDisplaysAboveAndLeftOfPrimary() {
    let shelf = CGRect(x: -300, y: 2209, width: 266, height: 40)
    #expect(WallpaperBackdrop.quartzFrame(shelf, primaryTop: 1169) ==
            CGRect(x: -300, y: -1080, width: 266, height: 40))
    #expect(WallpaperBackdrop.quartzFrame(CGRect(x: 1267, y: 1091, width: 266, height: 40), primaryTop: 1169) ==
            CGRect(x: 1267, y: 38, width: 266, height: 40))
}

@MainActor @Test func wallpaperRenderingCropsWithoutStretchingOrFlipping() throws {
    _ = NSApplication.shared
    let source = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 6, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    for y in 0..<2 { for x in 0..<6 {
        source.setColor(NSColor(deviceRed: CGFloat(x) / 5, green: CGFloat(y), blue: 0, alpha: 1), atX: x, y: y)
    } }
    let window = NSWindow(contentRect: CGRect(x: 2, y: 0, width: 2, height: 2),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = WallpaperSurfaceView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
    window.contentView = view
    view.snapshot = WallpaperSnapshot(image: try #require(source.cgImage), frame: CGRect(x: 0, y: 0, width: 6, height: 2))
    let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
        bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let rendered = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    for y in 0..<2 { for x in 0..<2 {
        let expected = try #require(source.colorAt(x: x + 2, y: y)?.usingColorSpace(.deviceRGB))
        let actual = try #require(rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        #expect(abs(expected.redComponent - actual.redComponent) < 0.01)
        #expect(abs(expected.greenComponent - actual.greenComponent) < 0.01)
        #expect(actual.alphaComponent == 1)
    } }
}
