import CoreGraphics
import Testing
@testable import TrayCore

@Test func missingFinalDragImageFollowsCurrentPointerInsteadOfStaleBarOverlap() throws {
    var image = StatusDragImage()
    #expect(image.frame(at: .zero) == nil)
    image.observe(frame: CGRect(x: 1480, y: 5, width: 40, height: 30), pointer: CGPoint(x: 1500, y: 20))
    let moved = try #require(image.frame(at: CGPoint(x: 1500, y: 100)))
    #expect(moved == CGRect(x: 1480, y: 85, width: 40, height: 30))
    #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1500, y: 100), image: moved,
        bar: CGRect(x: 0, y: 0, width: 1920, height: 30), trigger: CGRect(x: 1400, y: 0, width: 44, height: 30)) == nil)
}
