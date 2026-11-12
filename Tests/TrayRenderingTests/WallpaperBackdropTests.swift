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

@MainActor @Test func fullscreenBackdropOverridesWallpaperOnlyOnItsVisibleDisplay() {
    let desktop = Int(CGWindowLevelForKey(.desktopWindow))
    let display = CGRect(x: 1800, y: -271, width: 2560, height: 1440)
    let otherDisplay = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    func plane(_ id: CGWindowID, _ frame: CGRect, layer: Int, owner: String = "Dock",
               name: String = "Fullscreen Backdrop", alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation,
         kCGWindowOwnerName as String: owner, kCGWindowName as String: name,
         kCGWindowAlpha as String: alpha]
    }
    let wallpaper = plane(1, display, layer: desktop - 1, name: "Wallpaper-Example")
    let fullscreen = plane(2, display, layer: desktop + 1)
    // Selection must not depend on the input order or cached desktop content.
    #expect(WallpaperBackdrop.windowID(in: [wallpaper, fullscreen], display: display) == 2)
    #expect(WallpaperBackdrop.windowID(in: [fullscreen, wallpaper], display: display) == 2)
    for invalid in [
        plane(3, otherDisplay, layer: desktop + 1),
        plane(4, display, layer: desktop + 1, alpha: 0),
        plane(5, display, layer: 0),
        plane(6, display, layer: desktop + 1, owner: "Another app"),
        plane(7, display, layer: desktop + 1, name: "Another Dock window")
    ] {
        #expect(WallpaperBackdrop.windowID(in: [invalid, wallpaper], display: display) == 1)
    }
    #expect(WallpaperBackdrop.windowID(in: [wallpaper], display: display) == 1)
    #expect(WallpaperBackdrop.windowID(in: [fullscreen], display: display) == 2)
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

@MainActor @Test func menuBarEdgeSelectionUsesTheTargetDisplayOnly() throws {
    let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
    func window(_ id: CGWindowID, _ layer: CGWindowLevelKey, _ frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowLayer as String: Int(CGWindowLevelForKey(layer)),
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
    let bar = CGRect(x: -1920, y: -1080, width: 1920, height: 24)
    let windows = [window(1, .normalWindow, bar),
                   window(2, .mainMenuWindow, CGRect(x: 0, y: 0, width: 1800, height: 39)),
                   window(3, .mainMenuWindow, bar)]
    let selected = try #require(MenuBarGeometry.window(in: windows, display: display))
    #expect(selected.id == 3)
    #expect(selected.frame == bar)
    #expect(MenuBarGeometry.window(in: Array(windows.prefix(2)), display: display) == nil)
}


@MainActor @Test(arguments: [1, 2]) func shadowBlendFadesAboveTheBodyWithoutDarkeningWallpaper(scale: Int) throws {
    _ = NSApplication.shared
    let width = 80 * scale
    let bodyHeight = 30 * scale
    let join = 12 * scale
    let height = bodyHeight + join
    let source = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    for y in 0..<height { for x in 0..<width {
        source.setColor(NSColor(deviceRed: x.isMultiple(of: 2) ? 0.2 : 0.8,
            green: CGFloat(y) / CGFloat(height), blue: 0.6, alpha: 1), atX: x, y: y)
    } }
    let frame = CGRect(x: 100, y: 200, width: 80, height: 42)
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = WallpaperSurfaceView(frame: CGRect(origin: .zero, size: frame.size))
    window.contentView = view
    view.joinHeight = 12
    view.snapshot = WallpaperSnapshot(image: try #require(source.cgImage), frame: frame)
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let result = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    for y in 0..<height { for x in 0..<width {
        let expected = try #require(source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let actual = try #require(result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        // Compare premultiplied channels, allowing one byte of rounding when
        // a nearly transparent pixel is converted back to unassociated colour.
        #expect(abs((actual.redComponent - expected.redComponent) * actual.alphaComponent) < 0.005)
        #expect(abs((actual.blueComponent - expected.blueComponent) * actual.alphaComponent) < 0.005)
        if y >= join {
            #expect(actual.alphaComponent == 1)
            #expect(abs(actual.greenComponent - expected.greenComponent) < 0.01)
        } else if x == width / 2 {
            #expect(abs(actual.alphaComponent - (CGFloat(y) + 0.5) / CGFloat(join)) < 0.01)
        } else {
            let mirrored = try #require(result.colorAt(x: width - 1 - x, y: y)?.usingColorSpace(.deviceRGB))
            #expect(abs(actual.alphaComponent - mirrored.alphaComponent) < 0.005)
            if x == 0 && y < join / 2 { #expect(actual.alphaComponent < 0.005) }
        }
    } }
}

@MainActor @Test func shelfBlendStaysBelowNativeStatusIcons() {
    let panel = ShelfPanel()
    #expect(panel.level == .mainMenu)
    #expect(panel.level.rawValue < NSWindow.Level.statusBar.rawValue)
    #expect(!panel.hasShadow)
    panel.close()
}

@MainActor @Test func reservedStatusAreaRequiresTheMeasuredDisplayAndExcludesItsApplicationMenus() throws {
    let menuBar = CGRect(x: 0, y: 0, width: 1800, height: 39)
    let titles = [CGRect(x: 0, y: 0, width: 40, height: 39),
                  CGRect(x: 40, y: 0, width: 760, height: 39)]
    let area = try #require(MenuBarGeometry.statusArea(menuBar: menuBar, titles: titles, targetBar: menuBar))
    #expect(area == CGRect(x: 800, y: 0, width: 1000, height: 39))
    #expect(!area.intersects(CGRect(x: 0, y: 0, width: 800, height: 39)))
    let other = CGRect(x: -1920, y: -1080, width: 1920, height: 24)
    #expect(MenuBarGeometry.statusArea(menuBar: menuBar, titles: titles, targetBar: other) == nil)
    let otherTitles = [CGRect(x: -1920, y: -1080, width: 40, height: 24),
                       CGRect(x: -1880, y: -1080, width: 760, height: 24)]
    #expect(MenuBarGeometry.statusArea(menuBar: other, titles: otherTitles, targetBar: other) ==
            CGRect(x: -1120, y: -1080, width: 1120, height: 24))
    #expect(MenuBarGeometry.statusArea(menuBar: menuBar, titles: [], targetBar: menuBar) == nil)
    #expect(MenuBarGeometry.statusArea(menuBar: menuBar,
        titles: [CGRect(x: -10, y: 0, width: 40, height: 39)], targetBar: menuBar) == nil)
}
