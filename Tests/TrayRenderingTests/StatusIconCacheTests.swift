import AppKit
import Testing
import SwiftUI
@testable import Tray

@MainActor private func icon(alpha: UInt8) throws -> CGImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let data = Data([UInt8(0), 0, 0, alpha])
    return try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: CGDataProvider(data: data as CFData)!,
                               decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

@MainActor @Test func blankFirstCaptureUsesAppIcon() throws {
    var cache = StatusIconCache()
    let fallback = NSImage(size: CGSize(width: 18, height: 18))
    let result = cache.resolve(id: 1, sourcePID: 20, capture: try icon(alpha: 0),
                               size: CGSize(width: 30, height: 39), fallback: fallback)
    #expect(result.image === fallback)
    #expect(!result.isLiveImage)
}

@MainActor @Test func emptyAndFailedCapturesKeepTheLastVisibleIcon() throws {
    var cache = StatusIconCache()
    let size = CGSize(width: 30, height: 39)
    let good = cache.resolve(id: 1, sourcePID: 20, capture: try icon(alpha: 255), size: size, fallback: nil)
    #expect(good.isLiveImage)
    #expect(good.image?.size == size)
    let blank = cache.resolve(id: 1, sourcePID: 20, capture: try icon(alpha: 0), size: size, fallback: nil)
    let failed = cache.resolve(id: 1, sourcePID: 20, capture: nil, size: size, fallback: nil)
    #expect(blank.image === good.image && blank.isLiveImage)
    #expect(failed.image === good.image && failed.isLiveImage)
    let refreshed = cache.resolve(id: 1, sourcePID: 20, capture: try icon(alpha: 128), size: size, fallback: nil)
    #expect(refreshed.isLiveImage && refreshed.image !== good.image)
}

@MainActor @Test func cacheNeverReusesAnotherAppsIconAndDropsDeadWindows() throws {
    var cache = StatusIconCache()
    let size = CGSize(width: 30, height: 39)
    _ = cache.resolve(id: 1, sourcePID: 20, capture: try icon(alpha: 255), size: size, fallback: nil)
    let reused = cache.resolve(id: 1, sourcePID: 21, capture: nil, size: size, fallback: nil)
    #expect(reused.image == nil && !reused.isLiveImage)
    _ = cache.resolve(id: 2, sourcePID: 20, capture: try icon(alpha: 255), size: size, fallback: nil)
    cache.retain(windows: [1])
    let removed = cache.resolve(id: 2, sourcePID: 20, capture: nil, size: size, fallback: nil)
    #expect(removed.image == nil && !removed.isLiveImage)
}

@MainActor @Test func blackAndFaintIconsAreNotMistakenForBlankCaptures() throws {
    #expect(!StatusIconCache.hasVisiblePixels(try icon(alpha: 0)))
    #expect(StatusIconCache.hasVisiblePixels(try icon(alpha: 255)))
    #expect(StatusIconCache.hasVisiblePixels(try icon(alpha: 1)))
}

@MainActor @Test func iconEdgesRemainVisibleAgainstMatchingBackgrounds() throws {
    for white in [false, true] {
        let glyph = Rectangle().fill(white ? Color.white : Color.black)
            .frame(width: 10, height: 10)
            .modifier(StatusIconContrast())
            .frame(width: 30, height: 30)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        // The empty shelf remains clear, while pixels around the matching
        // black/black or white/white glyph provide a visible contrast edge.
        #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        var contrast: CGFloat = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let brightness = (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3
            contrast = max(contrast, colour.alphaComponent * (white ? 1 - brightness : brightness))
        } }
        #expect(contrast > 0.15)
    }
}
