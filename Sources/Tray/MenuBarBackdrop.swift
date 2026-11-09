import AppKit
import TrayCore

/// Captures the menu bar and the windows beneath it as one composite. This
/// preserves WindowServer's material while excluding overlays above the bar.
final class MenuBarBackdrop {
    struct Background: Equatable {
        let windowID: CGWindowID
        let barFrame: CGRect
    }

    private typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    nonisolated private static let capture: Capture? = {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(address, to: Capture.self)
    }()

    private var cacheKey = ""
    private var capturedAt: TimeInterval = 0
    private var cachedImage: NSImage?

    func invalidate() {
        cachedImage = nil
        cacheKey = ""
        capturedAt = 0
    }

    func background(for screen: NSScreen) -> Background? {
        guard let main = NSScreen.screens.first else { return nil }
        let display = CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY,
                             width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        func rect(_ info: [String: Any]) -> CGRect? {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard let bar = windows.first(where: { info in
            guard (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let frame = rect(info) else { return false }
            return abs(frame.minX - display.minX) < 2 && abs(frame.width - display.width) < 2 &&
                abs(frame.minY - display.minY) < 2 && frame.height >= 16 && frame.height <= 64
        }), let barFrame = rect(bar),
            let windowID = bar[kCGWindowNumber as String] as? CGWindowID else { return nil }
        return Background(windowID: windowID, barFrame: barFrame)
    }

    @concurrent static func refreshedImage(for background: Background, shelfFrame: CGRect, scale: CGFloat) async -> CGImage? {
        let sample = ShelfSurface.backgroundSample(barFrame: background.barFrame, shelfFrame: shelfFrame, scale: scale)
        guard !Task.isCancelled else { return nil }
        return captureMaterial(sample, windowID: background.windowID)
    }

    nonisolated private static func captureMaterial(_ sample: CGRect, windowID: CGWindowID) -> CGImage? {
        guard let image = capture?(sample,
                CGWindowListOption.optionOnScreenBelowWindow.union(.optionIncludingWindow).rawValue,
                windowID, CGWindowImageOption.bestResolution.rawValue)?.takeRetainedValue(),
              image.width > 0, image.height > 0 else { return nil }
        return image
    }

    func image(for background: Background, shelfFrame: CGRect, scale: CGFloat) -> NSImage? {
        // Preserve the material in both dimensions. Neither the outer
        // borders nor higher-level windows belong in the sample.
        let sample = ShelfSurface.backgroundSample(barFrame: background.barFrame, shelfFrame: shelfFrame, scale: scale)
        let key = "\(background.windowID)-\(sample)-\(scale)"
        let now = ProcessInfo.processInfo.systemUptime
        if key == cacheKey && now - capturedAt < 0.05 { return cachedImage }
        cacheKey = key
        capturedAt = now
        // Excluding everything above the actual menu-bar window prevents the
        // shelf, status highlights, and other overlays from tinting the sample.
        guard let cgImage = Self.captureMaterial(sample, windowID: background.windowID) else {
            cachedImage = nil
            return nil
        }
        cachedImage = NSImage(cgImage: cgImage, size: CGSize(width: sample.width, height: sample.height))
        return cachedImage
    }
}
