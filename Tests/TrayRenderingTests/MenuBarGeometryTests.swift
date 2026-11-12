import AppKit
import Testing
@testable import Tray

@MainActor @Test(arguments: [0.0, 0.5, 1.0])
func menuBarVisibilityFollowsTheTargetDisplay(alpha: Double) throws {
    let display = CGRect(x: 1800, y: -271, width: 2560, height: 1440)
    let otherDisplay = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    func bar(_ id: CGWindowID, display: CGRect, offset: CGFloat = 0, alpha: Double = 1) -> [String: Any] {
        let frame = CGRect(x: display.minX, y: display.minY + offset, width: display.width, height: 30)
        return [kCGWindowNumber as String: id,
                kCGWindowLayer as String: Int(CGWindowLevelForKey(.mainMenuWindow)),
                kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
    let otherBar = bar(1, display: otherDisplay)
    let targetBar = bar(2, display: display, alpha: alpha)
    let visible = MenuBarGeometry.window(in: [otherBar, targetBar], display: display)
    #expect(visible?.id == (alpha > 0 ? 2 : nil))
    // The desktop bar remains visible while fullscreen retracts its own bar.
    #expect(MenuBarGeometry.window(in: [otherBar], display: display) == nil)
    #expect(MenuBarGeometry.window(in: [otherBar], display: otherDisplay)?.id == 1)
    #expect(MenuBarGeometry.window(in: [otherBar, bar(2, display: display, offset: -10)], display: display) == nil)
    #expect(MenuBarGeometry.window(in: [], display: display) == nil)
}
