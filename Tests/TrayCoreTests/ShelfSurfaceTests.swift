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
func shelfUsesExactlyTheNativeBarHeightAndDoesNotCoverItsPixels(scale: CGFloat) {
    for height: CGFloat in [30, 39] {
        let bottom: CGFloat = 1169 - height
        let panel = ShelfSurface.frame(anchor: CGRect(x: 1350, y: bottom, width: 28, height: height),
                                       screen: CGRect(x: 0, y: 0, width: 1800, height: 1169),
                                       menuBarBottom: bottom, bodyWidth: 222, height: height, scale: scale)
        #expect(panel.maxY == bottom)
        #expect(panel.height == height)
        #expect(panel.minY * scale == (panel.minY * scale).rounded())
        #expect(!panel.intersects(CGRect(x: 0, y: bottom, width: 1800, height: height)))
        let mask = ShelfSurface.liquidPath(in: CGRect(origin: .zero, size: panel.size), progress: 1, originX: 133)
        #expect(mask.boundingBoxOfPath.minY == 0)
        #expect(mask.boundingBoxOfPath.height == height)
    }
}

@Test(arguments: [CGFloat(1), CGFloat(2)])
func shadowBlendKeepsTheBodyFlushAndItsShapeUnchanged(scale: CGFloat) {
    for height: CGFloat in [24, 30, 39] {
        let bottom: CGFloat = 1169 - height
        let body = ShelfSurface.frame(anchor: CGRect(x: 1350, y: bottom, width: 28, height: height),
            screen: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            menuBarBottom: bottom, bodyWidth: 222, height: height, scale: scale)
        let join = ShelfSurface.joinHeight(rowHeight: body.height)
        let panel = ShelfSurface.panelFrame(body: body, joinHeight: join)
        #expect(panel.minY == body.minY)
        #expect(panel.maxY - join == bottom)
        #expect(panel.height - join == height)
        #expect(panel.maxY * scale == (panel.maxY * scale).rounded())
        let original = ShelfSurface.path(in: CGRect(origin: .zero, size: body.size))
        let joined = ShelfSurface.liquidPath(in: CGRect(origin: .zero, size: panel.size),
            progress: 1, originX: 100, joinHeight: join)
        for x in stride(from: CGFloat(0), through: body.width, by: 2) {
            for y in stride(from: CGFloat(1), through: height - 1, by: 2) {
                #expect(joined.contains(CGPoint(x: x, y: y + join)) == original.contains(CGPoint(x: x, y: y)))
            }
        }
    }
}

@Test func theShadowJoinShrinksContinuouslyToTheClosedEndpoint() {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 51)
    let closed = ShelfSurface.liquidPath(in: bounds, progress: 0, originX: 240, joinHeight: 12)
    #expect(closed.isEmpty)
    for progress: CGFloat in [0.0001, 0.001, 0.01] {
        let path = ShelfSurface.liquidPath(in: bounds, progress: progress, originX: 240, joinHeight: 12)
        // Both the bridge and body must converge on zero width. A constant
        // six-point neck would leave a visible rectangle before disappearing.
        #expect(path.boundingBoxOfPath.width < bounds.width * progress * 2)
        #expect(path.boundingBoxOfPath.minY == 0)
    }
}

@Test func aWideBundleStaysInsideTheNativeStatusArea() {
    let statusArea = CGRect(x: 1000, y: 0, width: 800, height: 1169)
    let body = ShelfSurface.frame(anchor: CGRect(x: 1386, y: 1130, width: 28, height: 39),
        screen: statusArea, menuBarBottom: 1130, bodyWidth: 5000, height: 39, scale: 2)
    let panel = ShelfSurface.panelFrame(body: body, joinHeight: 12)
    #expect(panel.minX == 1008)
    #expect(panel.maxX == 1792)
    #expect(!panel.intersects(CGRect(x: 0, y: 1130, width: 1000, height: 39)))
    #expect(ShelfSurface.panelFrame(body: body, joinHeight: 0) == body)
}

@Test func joinTapersAtBothSidesAndMeetsTheOpaqueBody() {
    let width: CGFloat = 200
    let join: CGFloat = 12
    for y: CGFloat in [0, 3, 6, 9] {
        #expect(ShelfSurface.joinOpacity(at: CGPoint(x: 0, y: y), width: width, joinHeight: join) == 0)
        #expect(ShelfSurface.joinOpacity(at: CGPoint(x: width, y: y), width: width, joinHeight: join) == 0)
        for x: CGFloat in [0.25, 2, 5, 10, 22, 100] {
            let left = ShelfSurface.joinOpacity(at: CGPoint(x: x, y: y), width: width, joinHeight: join)
            let right = ShelfSurface.joinOpacity(at: CGPoint(x: width - x, y: y), width: width, joinHeight: join)
            #expect(abs(left - right) < 0.00001)
        }
    }
    for x: CGFloat in [0.25, 1, 5, 22, 100, 199.75] {
        let before = ShelfSurface.joinOpacity(at: CGPoint(x: x, y: join - 0.001), width: width, joinHeight: join)
        #expect(before > 0.999)
        #expect(ShelfSurface.joinOpacity(at: CGPoint(x: x, y: join), width: width, joinHeight: join) == 1)
    }
}
