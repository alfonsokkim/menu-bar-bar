import AppKit
import Testing
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

@MainActor @Test func blankFirstCaptureNeverSubstitutesAnAppLogo() throws {
    var cache = StatusIconCache()
    let result = cache.resolve(id: 1, sourcePID: 20, captures: [try icon(alpha: 0)],
                               size: CGSize(width: 30, height: 39))
    #expect(result.image == nil)
    #expect(!result.isLiveImage)
}

@MainActor @Test func emptyAndFailedCapturesKeepTheLastVisibleIcon() throws {
    var cache = StatusIconCache()
    let size = CGSize(width: 30, height: 39)
    let good = cache.resolve(id: 1, sourcePID: 20, captures: [try icon(alpha: 255)], size: size)
    #expect(good.isLiveImage)
    #expect(good.image?.size == size)
    let blank = cache.resolve(id: 1, sourcePID: 20, captures: [try icon(alpha: 0)], size: size)
    let failed = cache.resolve(id: 1, sourcePID: 20, captures: [], size: size)
    #expect(blank.image === good.image && blank.isLiveImage)
    #expect(failed.image === good.image && failed.isLiveImage)
    let refreshed = cache.resolve(id: 1, sourcePID: 20, captures: [try icon(alpha: 128)], size: size)
    #expect(refreshed.isLiveImage && refreshed.image !== good.image)
}

@MainActor @Test func freshMirrorReplacesOldCaptureAndSurvivesMirrorRemoval() throws {
    var cache = StatusIconCache()
    let size = CGSize(width: 38, height: 39)
    let old = cache.resolve(id: 10, sourcePID: 20, captures: [try icon(alpha: 255)], size: size)
    // The canonical window is blank, but its mirror supplies a new image.
    let fresh = cache.resolve(id: 10, sourcePID: 20,
                              captures: [try icon(alpha: 0), try icon(alpha: 128)], size: size)
    #expect(fresh.isLiveImage && fresh.image !== old.image)
    cache.retain(windows: [10])
    let withoutMirror = cache.resolve(id: 10, sourcePID: 20, captures: [], size: size)
    #expect(withoutMirror.isLiveImage && withoutMirror.image === fresh.image)
}

@MainActor @Test func cacheNeverReusesAnotherAppsIconAndDropsDeadWindows() throws {
    var cache = StatusIconCache()
    let size = CGSize(width: 30, height: 39)
    _ = cache.resolve(id: 1, sourcePID: 20, captures: [try icon(alpha: 255)], size: size)
    let reused = cache.resolve(id: 1, sourcePID: 21, captures: [], size: size)
    #expect(reused.image == nil && !reused.isLiveImage)
    _ = cache.resolve(id: 2, sourcePID: 20, captures: [try icon(alpha: 255)], size: size)
    cache.retain(windows: [1])
    let removed = cache.resolve(id: 2, sourcePID: 20, captures: [], size: size)
    #expect(removed.image == nil && !removed.isLiveImage)
}

@MainActor @Test func blackAndFaintIconsAreNotMistakenForBlankCaptures() throws {
    #expect(!StatusIconCache.hasVisiblePixels(try icon(alpha: 0)))
    #expect(StatusIconCache.hasVisiblePixels(try icon(alpha: 255)))
    #expect(StatusIconCache.hasVisiblePixels(try icon(alpha: 1)))
}

@MainActor @Test func hostedMirrorsNeverAddDuplicateIcons() {
    let frame = CGRect(x: -4000, y: 0, width: 38, height: 39)
    func item(_ id: CGWindowID, _ source: pid_t, _ bounds: CGRect, live: Bool) -> MenuItem {
        MenuItem(id: id, pid: 762, sourcePID: source, name: "Utility", frame: bounds,
                 image: nil, isLiveImage: live)
    }
    let native = item(10, 20, frame, live: true)
    let mirror = item(30, 20, frame, live: false)
    let secondExtra = item(40, 20, frame.offsetBy(dx: 38, dy: 0), live: true)
    let otherApp = item(50, 21, frame, live: true)
    #expect(MenuItems.deduplicated([mirror, native, secondExtra, otherApp]).map(\.id) == [10, 40, 50])
    #expect(MenuItems.deduplicated([native, mirror]).map(\.id) == [10])
    #expect(MenuItems.deduplicated([mirror, item(10, 20, frame, live: false)]).map(\.id) == [10])
    let capturedMirror = MenuItems.deduplicated([item(10, 20, frame, live: false), item(30, 20, frame, live: true)])
    #expect(capturedMirror.map(\.id) == [10])
}
