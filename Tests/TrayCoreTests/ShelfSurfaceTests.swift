import CoreGraphics
import Testing
@testable import TrayCore

@Test func shouldersWidenIntoTheMenuBar() {
    let path = ShelfSurface.path(in: CGRect(x: 0, y: 0, width: 200, height: 45))
    #expect(path.contains(CGPoint(x: 10, y: 1)))
    #expect(!path.contains(CGPoint(x: 10, y: 20)))
    #expect(path.contains(CGPoint(x: 25, y: 20)))
    #expect(!path.contains(CGPoint(x: 23, y: 44)))
    #expect(path.contains(CGPoint(x: 100, y: 44)))
    for x in stride(from: CGFloat(0), through: 200, by: 2) {
        for y in stride(from: CGFloat(1), through: 44, by: 2) {
            #expect(path.contains(CGPoint(x: x, y: y)) == path.contains(CGPoint(x: 200 - x, y: y)))
        }
    }
}

@Test(arguments: [CGFloat(1), CGFloat(2)])
func joinMeetsMenuBarWithoutOverlap(scale: CGFloat) {
    let frame = ShelfSurface.frame(anchor: CGRect(x: -200, y: 1050, width: 44, height: 30),
                                    screen: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                    menuBarBottom: 1050, bodyWidth: 160, height: 30, scale: scale)
    #expect(frame.maxY == 1050)
    #expect(frame.height == 30)
    #expect(frame.minY == 1020)
    #expect(1050 - frame.minY == 30)
    #expect(frame.width == 204)
    #expect(frame.minX * scale == (frame.minX * scale).rounded())
}

@Test func nativeStatusWidthsRemainUnchanged() {
    #expect(ShelfSurface.cellWidth(itemWidth: 22) == 22)
    #expect(ShelfSurface.cellWidth(itemWidth: 30) == 30)
    #expect(ShelfSurface.cellWidth(itemWidth: 31) == 31)
    #expect(ShelfSurface.cellWidth(itemWidth: 80) == 80)
}

@Test func flaresFitWhenTheShelfReachesADisplayEdge() {
    let screen = CGRect(x: 0, y: -1200, width: 1600, height: 1200)
    let frame = ShelfSurface.frame(anchor: CGRect(x: 1570, y: -30, width: 30, height: 30),
                                    screen: screen, menuBarBottom: -30, bodyWidth: 5000, height: 44, scale: 2)
    #expect(frame.minX == 8)
    #expect(frame.maxX == 1592)
    #expect(frame.maxY == -30)
}

@Test func liquidRevealKeepsTheJoinAndSettledShape() {
    let rect = CGRect(x: 7, y: 11, width: 200, height: 30)
    #expect(ShelfSurface.liquidPath(in: rect, progress: 0, originX: 160).isEmpty)
    #expect(ShelfSurface.liquidPath(in: rect, progress: 1, originX: 160) == ShelfSurface.path(in: rect))
    for origin in [CGFloat(0), 100, 200] {
        for progress in stride(from: CGFloat(0.05), through: 1.15, by: 0.05) {
            let bounds = ShelfSurface.liquidPath(in: rect, progress: progress, originX: origin).boundingBoxOfPath
            #expect(abs(bounds.minY - rect.minY) < 0.001)
            #expect(bounds.maxY <= rect.maxY + 0.001)
            #expect(bounds.minX >= rect.minX - 0.001)
            #expect(bounds.maxX <= rect.maxX + 0.001)
        }
    }
}

@Test func dropletStartsUnderTheTriggerBeforeSpreading() {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 30)
    let early = ShelfSurface.liquidPath(in: rect, progress: 0.1, originX: 240).boundingBoxOfPath
    let late = ShelfSurface.liquidPath(in: rect, progress: 0.8, originX: 240).boundingBoxOfPath
    #expect(early.midX > 220)
    #expect(early.width < 45)
    #expect(late.width > early.width * 3)
    #expect(late.height > early.height)
    #expect(abs(late.midX - rect.midX) < abs(early.midX - rect.midX))
}

@Test(arguments: [CGFloat(1), CGFloat(2)])
func separatorCoverPreservesTheBodyAndFollowsTheReveal(scale: CGFloat) {
    let body = CGRect(x: -200, y: 1020, width: 82, height: 30)
    let panel = ShelfSurface.panelFrame(bodyFrame: body, scale: scale)
    let join = 1 / scale
    #expect(panel.minY == body.minY)
    #expect(panel.maxY == body.maxY + join)
    #expect(panel.width == body.width)
    let bounds = CGRect(origin: .zero, size: panel.size)
    let settled = ShelfSurface.liquidPath(in: bounds, progress: 1, originX: 41, joinHeight: join)
    let original = ShelfSurface.path(in: CGRect(x: 0, y: join, width: body.width, height: body.height))
    #expect(settled.contains(CGPoint(x: 41, y: join / 2)))
    for x in stride(from: CGFloat(1), to: 82, by: 2) {
        for y in stride(from: join + 0.25, to: panel.height, by: 0.5) {
            #expect(settled.contains(CGPoint(x: x, y: y)) == original.contains(CGPoint(x: x, y: y)))
        }
    }
    let early = ShelfSurface.liquidPath(in: bounds, progress: 0.1, originX: 41, joinHeight: join)
    #expect(early.contains(CGPoint(x: 41, y: join / 2)))
    #expect(!early.contains(CGPoint(x: 5, y: join / 2)))
    #expect(ShelfSurface.liquidPath(in: bounds, progress: 0, originX: 41, joinHeight: join).isEmpty)
}
