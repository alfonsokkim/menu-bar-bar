import AppKit

/// Offscreen status windows sometimes return a valid, entirely clear bitmap.
/// Keep the last visible capture instead of replacing an icon with empty pixels.
struct StatusIconCache {
    private struct Entry {
        let sourcePID: pid_t
        let image: NSImage
    }
    private var entries: [CGWindowID: Entry] = [:]

    mutating func retain(windows: Set<CGWindowID>) {
        entries = entries.filter { windows.contains($0.key) }
    }

    mutating func resolve(id: CGWindowID, sourcePID: pid_t, capture: CGImage?,
                          size: CGSize, fallback: NSImage?) -> (image: NSImage?, isLiveImage: Bool) {
        if entries[id]?.sourcePID != sourcePID { entries[id] = nil }
        if let capture, Self.hasVisiblePixels(capture) {
            entries[id] = Entry(sourcePID: sourcePID, image: NSImage(cgImage: capture, size: size))
        }
        if let entry = entries[id] { return (entry.image, true) }
        return (fallback, false)
    }

    static func hasVisiblePixels(_ image: CGImage) -> Bool {
        guard image.width > 0, image.height > 0,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return false }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: context.bytesPerRow * image.height, by: 4).contains { bytes[$0] > 0 }
    }
}
