import AppKit
import TrayCore

/// Draw the same interior colour on both sides of the native bar's edge.
/// The upper half of the blend leaves the native material untouched.
enum MenuMaterialBlend {
    static func interiorRow(of image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = image.colorSpace,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = bitmap.data else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let rows = (height / 3)..<max(height / 3 + 1, height * 2 / 3)
        var row = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width {
            for channel in 0..<4 {
                var sum = 0
                for y in rows { sum += Int(bytes[y * width * 4 + x * 4 + channel]) }
                row[x * 4 + channel] = UInt8((sum + rows.count / 2) / rows.count)
            }
        }
        guard let provider = CGDataProvider(data: Data(row) as CFData) else { return nil }
        return CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func draw(row: CGImage, in context: CGContext, bounds: CGRect,
                     sampleX: CGFloat, sampleWidth: CGFloat, fadeUpward: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.normal)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.interpolationQuality = .low
        context.draw(row, in: CGRect(x: sampleX, y: bounds.minY, width: sampleWidth, height: bounds.height))
        context.setBlendMode(.destinationIn)
        let clear = CGColor(gray: 1, alpha: 0), opaque = CGColor(gray: 1, alpha: 1)
        let shoulder = min(ShelfSurface.flare / bounds.width, 0.5)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                     colors: [clear, opaque, opaque, clear] as CFArray,
                                     locations: [0, shoulder, 1 - shoulder, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.midY),
                                       end: CGPoint(x: bounds.maxX, y: bounds.midY), options: [])
        }
        if fadeUpward, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                                 colors: [opaque, clear] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.minY),
                                       end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
        }
        context.endTransparencyLayer()
    }
}

/// Paint below the native status windows and above the menu material. This
/// window never receives input or changes the interactive shelf's frame.
final class MenuMaterialBridge: NSPanel {
    private let materialView = BridgeView()
    private var placementTask: Task<Void, Never>?
    private var barWindowID: CGWindowID = 0
    private(set) var isReady = false
    var placementDidChange: (() -> Void)?
    private typealias Connection = @convention(c) () -> Int32
    private typealias Sublevel = @convention(c) (Int32, CGWindowID, Int32) -> Int32
    private static let placement: (Connection, Sublevel)? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(handle, "CGSMainConnectionID"),
              let sublevel = dlsym(handle, "SLSSetWindowSubLevel") else { return nil }
        return (unsafeBitCast(connection, to: Connection.self), unsafeBitCast(sublevel, to: Sublevel.self))
    }()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Menu Bar Bar Material Join"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        contentView = materialView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(frame: CGRect, row: CGImage, barWindowID: CGWindowID, sampleFrame: CGRect,
                reveal: CGFloat, originX: CGFloat, rowHeight: CGFloat, reduceMotion: Bool) {
        if self.frame != frame { setFrame(frame, display: false) }
        materialView.row = row
        materialView.sampleX = sampleFrame.minX - frame.minX
        materialView.sampleWidth = sampleFrame.width
        materialView.reveal = reveal
        materialView.originX = originX
        materialView.rowHeight = rowHeight
        materialView.reduceMotion = reduceMotion
        materialView.needsDisplay = true
        self.barWindowID = barWindowID
        let opening = !isVisible
        if opening {
            alphaValue = 0
            orderFront(nil)
        }
        guard let (connection, sublevel) = Self.placement,
              sublevel(connection(), CGWindowID(windowNumber), -1) == 0 else {
            orderOut(nil)
            return
        }
        if opening {
            // AppKit's order request reaches WindowServer at the next display
            // turn. Keep the bridge transparent until its position is proven.
            placementTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.placementTask = nil
                self.verifyPlacement()
            }
        } else if placementTask == nil {
            verifyPlacement()
        }
    }

    override func orderOut(_ sender: Any?) {
        placementTask?.cancel()
        placementTask = nil
        let wasReady = isReady
        isReady = false
        alphaValue = 0
        super.orderOut(sender)
        if wasReady { placementDidChange?() }
    }

    override func close() {
        orderOut(nil)
        super.close()
    }

    private func verifyPlacement() {
        guard isVisible, let main = NSScreen.screens.first else { orderOut(nil); return }
        // A private setter's success is not proof of global placement. Hide
        // the bridge unless WindowServer confirms both sides of the stack.
        let quartzFrame = CGRect(x: frame.minX, y: main.frame.maxY - frame.maxY,
                                 width: frame.width, height: frame.height)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        guard Self.placementIsValid(windows: windows, ownID: CGWindowID(windowNumber),
                                    barID: barWindowID, frame: quartzFrame) else {
            orderOut(nil)
            return
        }
        if !isReady {
            isReady = true
            alphaValue = 1
            placementDidChange?()
        }
    }

    static func placementIsValid(windows: [[String: Any]], ownID: CGWindowID,
                                  barID: CGWindowID, frame: CGRect) -> Bool {
        func id(_ info: [String: Any]) -> CGWindowID? { info[kCGWindowNumber as String] as? CGWindowID }
        guard let ownIndex = windows.firstIndex(where: { id($0) == ownID }),
              let barIndex = windows.firstIndex(where: { id($0) == barID }), ownIndex < barIndex else { return false }
        for (index, info) in windows.enumerated() {
            guard id(info) != ownID,
                  (info[kCGWindowLayer as String] as? Int) == NSWindow.Level.statusBar.rawValue,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            if rect.intersects(frame) && index > ownIndex { return false }
        }
        return true
    }
}

private final class BridgeView: NSView {
    var row: CGImage?
    var sampleX: CGFloat = 0
    var sampleWidth: CGFloat = 0
    var reveal: CGFloat = 0
    var originX: CGFloat = 0
    var rowHeight: CGFloat = 0
    var reduceMotion = false

    override func draw(_ dirtyRect: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.saveGState()
        defer { context.restoreGState() }
        // Use the shelf's actual animated mask for the upper span as well.
        let path = ShelfSurface.liquidPath(in: CGRect(x: 0, y: 0, width: bounds.width,
                                                     height: bounds.height + rowHeight),
                                          progress: reduceMotion ? 1 : reveal, originX: originX, joinHeight: bounds.height)
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        if let clip = path.copy(using: &flip) { context.addPath(clip); context.clip() }
        context.setAlpha(min(1, max(0, reveal)))
        MenuMaterialBlend.draw(row: row, in: context, bounds: bounds,
                               sampleX: sampleX, sampleWidth: sampleWidth, fadeUpward: true)
    }
}
