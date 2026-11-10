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


@Test func interruptedChevronKeepsItsVisiblePositionAndOpacity() {
    let opening = ChevronTransition(opening: true, phase: 0, began: 10)
    let interrupted = opening.phase(at: 10.055)
    let closing = ChevronTransition(opening: false, phase: interrupted, began: 10.055)
    #expect(abs(interrupted - 0.25) < 0.0001)
    #expect(closing.phase(at: 10.055) == interrupted)
    let center = CGPoint(x: 20, y: 15)
    let before = ChevronGeometry.strokes(phase: interrupted, center: center, travel: 70)
    let after = ChevronGeometry.strokes(phase: closing.phase(at: 10.055), center: center, travel: 70)
    #expect(before[0].start == after[0].start)
    #expect(ChevronGeometry.opacity(phase: interrupted) == ChevronGeometry.opacity(phase: closing.start))
    let returning = closing.phase(at: 10.08)
    let reopening = ChevronTransition(opening: true, phase: returning, began: 10.08)
    #expect(reopening.start == returning)
    #expect(reopening.phase(at: 20) == 0.6)
    #expect(closing.phase(at: 20) == 0)
}

@Test func chevronTransitionSkipsOnlyTheInvisiblePartOfItsTrajectory() {
    let opening = ChevronTransition(opening: true, phase: 0, began: 3)
    #expect(abs(opening.duration - 0.132) < 0.0001)
    #expect(opening.phase(at: 0) == 0)
    #expect(opening.phase(at: 10) == 0.6)
    #expect(ChevronGeometry.opacity(phase: opening.target) == 0)
    let closing = ChevronTransition(opening: false, phase: 1, began: 3)
    #expect(closing.start == 0.6)
    #expect(abs(closing.duration - opening.duration) < 0.0001)
    #expect(closing.phase(at: 10) == 0)
    let stopped = ChevronTransition(opening: false, phase: 0, began: 0)
    #expect(stopped.duration.isFinite && stopped.duration > 0)
    #expect(stopped.phase(at: 1) == 0)
}
