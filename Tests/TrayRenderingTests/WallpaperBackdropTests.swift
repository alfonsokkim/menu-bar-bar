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

@MainActor @Test(arguments: [1, 2]) func wallpaperJoinMatchesNativeEdgeAndPreservesLowerDetail(scale: Int) throws {
    let width = 6 * scale
    let height = 20 * scale
    let rows = 12 * scale
    func bitmap(_ height: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }
    let wallpaper = try bitmap(height)
    let edge = try bitmap(1)
    for x in 0..<width {
        // Different correction signs on neighbouring columns catch averaging
        // or stretching the edge instead of keeping its screen coordinates.
        edge.setColor(NSColor(deviceRed: x.isMultiple(of: 2) ? 0.3 : 0.7,
                              green: 0.5, blue: 0.5, alpha: 1), atX: x, y: 0)
        for y in 0..<height {
            wallpaper.setColor(NSColor(deviceRed: 0.5 + CGFloat(y) / 255,
                                       green: 0.4, blue: 0.6, alpha: 1), atX: x, y: y)
        }
    }
    let wallpaperImage = try #require(wallpaper.cgImage)
    let edgeImage = try #require(edge.cgImage)
    let joined = try #require(WallpaperBackdrop.joinedImage(
        wallpaper: wallpaperImage, edge: edgeImage, transitionPixels: rows))
    let result = NSBitmapImageRep(cgImage: joined)
    for x in 0..<width {
        let native = try #require(edge.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
        let top = try #require(result.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(abs(native.redComponent - top.redComponent) < 0.01)
        #expect(abs(native.greenComponent - top.greenComponent) < 0.01)
        #expect(abs(native.blueComponent - top.blueComponent) < 0.01)
        for y in (rows - 1)..<height {
            let original = try #require(wallpaper.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            let actual = try #require(result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            #expect(abs(original.redComponent - actual.redComponent) < 0.01)
            #expect(abs(original.greenComponent - actual.greenComponent) < 0.01)
            #expect(abs(original.blueComponent - actual.blueComponent) < 0.01)
            #expect(actual.alphaComponent == 1)
        }
        // The transition must not introduce another hard colour step.
        for y in 1...rows {
            let previous = try #require(result.colorAt(x: x, y: y - 1)?.usingColorSpace(.deviceRGB))
            let current = try #require(result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            #expect(abs(previous.redComponent - current.redComponent) < 0.04)
        }
    }
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

@MainActor @Test func nativeEdgeRejectsRedactedAndEmptyCapturesButPreservesDarkBars() throws {
    func material(fill: NSColor, glyph: Bool = false, colouredBottom: Bool = false, transparentBottom: Bool = false) throws -> CGImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<3 { for x in 0..<4 { bitmap.setColor(fill, atX: x, y: y) } }
        if glyph { bitmap.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: 1, y: 0) }
        if colouredBottom { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 2, y: 2) }
        if transparentBottom {
            for x in 0..<4 { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: 2) }
        }
        return try #require(bitmap.cgImage)
    }
    let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
    let empty = try material(fill: NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0))
    #expect(WallpaperBackdrop.nativeEdge(from: empty) == nil)
    let redacted = try material(fill: black)
    #expect(WallpaperBackdrop.nativeEdge(from: redacted) == nil)
    // A white menu glyph proves this is a real black bar, not an empty capture.
    let emptyBottom = try material(fill: black, glyph: true, transparentBottom: true)
    #expect(WallpaperBackdrop.nativeEdge(from: emptyBottom) == nil)
    let dark = try material(fill: black, glyph: true)
    let edge = try #require(WallpaperBackdrop.nativeEdge(from: dark))
    #expect(edge.width == 4 && edge.height == 1)
    let bottom = NSBitmapImageRep(cgImage: edge)
    for x in 0..<4 {
        let colour = try #require(bottom.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(colour.redComponent == 0 && colour.greenComponent == 0 && colour.blueComponent == 0)
        #expect(colour.alphaComponent == 1)
    }
    let coloured = try material(fill: black, glyph: true, colouredBottom: true)
    let colouredEdge = try #require(WallpaperBackdrop.nativeEdge(from: coloured))
    let pixel = try #require(NSBitmapImageRep(cgImage: colouredEdge).colorAt(x: 2, y: 0)?.usingColorSpace(.deviceRGB))
    #expect(pixel.redComponent == 1 && pixel.greenComponent == 0 && pixel.blueComponent == 0)
}

@MainActor @Test func wallpaperJoinCompositesPartialAlphaAndLeavesMissingColumnsUntouched() throws {
    let wallpaper = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 4,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let edge = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    for y in 0..<4 { for x in 0..<2 {
        wallpaper.setColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.6, alpha: 1), atX: x, y: y)
    } }
    edge.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: 0, y: 0)
    edge.setColor(NSColor(deviceRed: 0.8, green: 0, blue: 0, alpha: 0.5), atX: 1, y: 0)
    let source = try #require(wallpaper.cgImage)
    let sample = try #require(edge.cgImage)
    let joined = try #require(WallpaperBackdrop.joinedImage(wallpaper: source, edge: sample, transitionPixels: 3))
    let result = NSBitmapImageRep(cgImage: joined)
    for y in 0..<4 {
        let unchanged = try #require(result.colorAt(x: 0, y: y)?.usingColorSpace(.deviceRGB))
        #expect(abs(unchanged.redComponent - 0.2) < 0.01)
        #expect(abs(unchanged.greenComponent - 0.4) < 0.01)
        #expect(abs(unchanged.blueComponent - 0.6) < 0.01)
        #expect(unchanged.alphaComponent == 1)
    }
    let composite = try #require(result.colorAt(x: 1, y: 0)?.usingColorSpace(.deviceRGB))
    #expect(abs(composite.redComponent - 0.5) < 0.01)
    #expect(abs(composite.greenComponent - 0.2) < 0.01)
    #expect(abs(composite.blueComponent - 0.3) < 0.01)
    #expect(composite.alphaComponent == 1)
}
