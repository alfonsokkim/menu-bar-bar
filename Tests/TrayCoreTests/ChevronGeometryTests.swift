import CoreGraphics
import Testing
@testable import TrayCore

@Test func chevronInvertsInPlaceWithoutLosingItsArms() {
    let center = CGPoint(x: 9, y: 9)
    let down = ChevronGeometry.points(progress: 0, center: center)
    let up = ChevronGeometry.points(progress: 1, center: center)
    #expect(down[1].y > down[0].y)
    #expect(up[1].y < up[0].y)
    for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
        let points = ChevronGeometry.points(progress: progress, center: center)
        #expect(points.count == 3)
        #expect(points.map(\.x) == [5, 9, 13])
        #expect(points[0].y == points[2].y)
        #expect(points[0].y + points[1].y == 18)
        #expect(points.allSatisfy { abs($0.y - center.y) <= 2 })
    }
    #expect(ChevronGeometry.points(progress: 0.5, center: center).allSatisfy { $0.y == center.y })
    #expect(ChevronGeometry.points(progress: -1, center: center) == down)
    #expect(ChevronGeometry.points(progress: 2, center: center) == up)
}
