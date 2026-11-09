import CoreGraphics
import Testing
@testable import TrayCore

@Test func chevronFallsAcrossTheMenuBarAndDissolves() {
    let center = CGPoint(x: 22, y: 15)
    let closed = ChevronGeometry.strokes(phase: 0, center: center, travel: 35)
    let middle = ChevronGeometry.strokes(phase: 0.5, center: center, travel: 35)
    let falling = ChevronGeometry.strokes(phase: 0.8, center: center, travel: 35)
    #expect(closed[0].end == closed[1].start)
    #expect(closed[0].end.y > closed[0].start.y)
    #expect(middle[0].start.y > closed[0].start.y)
    #expect(falling[0].start.y > 30)
    #expect(falling[0].end.x == falling[1].start.x)
    #expect(ChevronGeometry.opacity(phase: 0) == 1)
    #expect(middle[0].start.x == closed[0].start.x)
    #expect(middle[0].start.y - closed[0].start.y == 35 * 0.25)
    #expect(ChevronGeometry.opacity(phase: 0.3) > 0)
    #expect(ChevronGeometry.opacity(phase: 0.3) < 1)
    #expect(ChevronGeometry.opacity(phase: 0.6) == 0)
    #expect(ChevronGeometry.opacity(phase: 1) == 0)
}

@Test func freeFallAcceleratesFromRestWithoutSidewaysMotion() {
    let center = CGPoint(x: 22, y: 15)
    let positions = [CGFloat(0), 0.1, 0.2, 0.3].map {
        ChevronGeometry.strokes(phase: $0, center: center, travel: 50)[0].start
    }
    let first = positions[1].y - positions[0].y
    let second = positions[2].y - positions[1].y
    let third = positions[3].y - positions[2].y
    #expect(abs(first - 0.5) < 0.001)
    #expect(abs(second - 1.5) < 0.001)
    #expect(abs(third - 2.5) < 0.001)
    #expect(positions.allSatisfy { $0.x == positions[0].x })
}
