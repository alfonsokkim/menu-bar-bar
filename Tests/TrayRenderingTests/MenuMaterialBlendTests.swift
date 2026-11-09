import AppKit
import Testing
@testable import Tray

@MainActor @Test func interiorColourExcludesTheDarkOuterRows() throws {
    // Two columns with different colours, surrounded by dark edge shading.
    let bytes: [UInt8] = [
        0,0,0,255, 0,0,0,255,
        0,0,0,255, 0,0,0,255,
        40,80,120,255, 120,80,40,255,
        60,100,140,255, 140,100,60,255,
        0,0,0,255, 0,0,0,255,
        0,0,0,255, 0,0,0,255
    ]
    let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let source = try #require(CGImage(width: 2, height: 6, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: 8, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: CGDataProvider(data: Data(bytes) as CFData)!,
                                     decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let row = try #require(MenuMaterialBlend.interiorRow(of: source))
    #expect(row.width == 2 && row.height == 1)
    #expect(row.colorSpace?.name == CGColorSpace.displayP3)
    let data = try #require(row.dataProvider?.data) as Data
    #expect(Array(data) == [50,90,130,255, 130,90,50,255])
}

@MainActor @Test func joinFadesIntoTheNativeBarAndAcrossBothShoulders() throws {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let source = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: 4, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: CGDataProvider(data: Data([UInt8(80),120,160,255]) as CFData)!,
                                     decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let context = try #require(CGContext(data: nil, width: 100, height: 20, bitsPerComponent: 8,
                                         bytesPerRow: 400, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    MenuMaterialBlend.draw(row: source, in: context, bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
                           sampleX: 0, sampleWidth: 100, fadeUpward: true)
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[y * 400 + x * 4 + 3] }
    // Bitmap rows start at the top, opposite AppKit's y coordinate.
    #expect(alpha(50, 0) < 10)
    #expect(alpha(50, 19) > 240)
    #expect(alpha(0, 19) < 10)
    #expect(alpha(99, 19) < 10)
    #expect(alpha(50, 10) > alpha(50, 5))
}

@MainActor @Test func materialJoinCannotInterceptInput() {
    _ = NSApplication.shared
    let bridge = MenuMaterialBridge()
    defer { bridge.close() }
    #expect(bridge.ignoresMouseEvents)
    #expect(!bridge.canBecomeKey && !bridge.canBecomeMain)
    #expect(!bridge.hasShadow)
    #expect(bridge.level == .statusBar)
    #expect(bridge.level.rawValue > Int(CGWindowLevelForKey(.mainMenuWindow)))
}

@MainActor @Test func joinRequiresVerifiedPlacementBetweenIconsAndNativeMaterial() {
    let frame = CGRect(x: 100, y: 15, width: 200, height: 15)
    func window(_ id: CGWindowID, _ level: Int, _ rect: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowLayer as String: level,
         kCGWindowBounds as String: rect.dictionaryRepresentation, kCGWindowAlpha as String: 1.0]
    }
    let icon = window(1, 25, CGRect(x: 120, y: 0, width: 30, height: 30))
    let bridge = window(2, 25, frame)
    let bar = window(3, 24, CGRect(x: 0, y: 0, width: 1000, height: 30))
    let otherDisplay = window(4, 25, CGRect(x: 1200, y: -1080, width: 30, height: 30))
    #expect(MenuMaterialBridge.placementIsValid(windows: [icon, bridge, otherDisplay, bar], ownID: 2, barID: 3, frame: frame))
    #expect(!MenuMaterialBridge.placementIsValid(windows: [bridge, icon, bar], ownID: 2, barID: 3, frame: frame))
    #expect(!MenuMaterialBridge.placementIsValid(windows: [icon, bar, bridge], ownID: 2, barID: 3, frame: frame))
    #expect(!MenuMaterialBridge.placementIsValid(windows: [icon, bar], ownID: 2, barID: 3, frame: frame))
    #expect(!MenuMaterialBridge.placementIsValid(windows: [icon, bridge], ownID: 2, barID: 3, frame: frame))
}
