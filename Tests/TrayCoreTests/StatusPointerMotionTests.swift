import CoreGraphics
import Testing
@testable import TrayCore

@Test func recordedOffscreenJumpIsNotPhysicalMovement() {
    let start = CGPoint(x: 1379.085938, y: 9.550781)
    let down = CGPoint(x: 1378, y: 15)
    let up = CGPoint(x: -1920, y: 15)
    var motion = StatusPointerMotion(at: start, timestamp: 100)
    motion.relocate(from: start, to: down, timestamp: 110)
    motion.relocate(from: down, to: up, timestamp: 120)
    // These samples previously included a reported delta of -3299 pixels.
    for (index, y) in [15.082031, 15.453125, 15.726562, 15.867188].enumerated() {
        motion.observe(at: CGPoint(x: -1920, y: y), timestamp: UInt64(130 + index))
    }
    #expect(abs(motion.destination.x - start.x) < 0.00001)
    #expect(abs(motion.destination.y - 10.417969) < 0.00001)
}

@Test func stalePreWarpSampleAfterMarkerDoesNotMoveCursorBack() {
    var motion = StatusPointerMotion(at: CGPoint(x: 100, y: 100), timestamp: 10)
    motion.relocate(from: CGPoint(x: 104, y: 102), to: CGPoint(x: -1920, y: 15), timestamp: 30)
    // The pre-post snapshot has already accounted for this older movement.
    motion.observe(at: CGPoint(x: 104, y: 102), timestamp: 20)
    #expect(motion.destination == CGPoint(x: 104, y: 102))
    motion.observe(at: CGPoint(x: -1917, y: 16), timestamp: 50)
    #expect(motion.destination == CGPoint(x: 107, y: 103))
}

@Test func movementBetweenTwoRelocationsIsPreserved() {
    var motion = StatusPointerMotion(at: CGPoint(x: 100, y: 100), timestamp: 10)
    motion.relocate(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 1400, y: 15), timestamp: 20)
    motion.observe(at: CGPoint(x: 1408, y: 18), timestamp: 30)
    motion.relocate(from: CGPoint(x: 1408, y: 18), to: CGPoint(x: -1920, y: 15), timestamp: 40)
    motion.observe(at: CGPoint(x: -1916, y: 17), timestamp: 50)
    #expect(motion.destination == CGPoint(x: 112, y: 105))
    motion.observe(at: CGPoint(x: -1910, y: 20), timestamp: 60)
    #expect(motion.destination == CGPoint(x: 118, y: 108))
}

@Test func fastPhysicalMotionTowardOldPositionIsNotMisclassified() {
    var motion = StatusPointerMotion(at: CGPoint(x: 0, y: 0), timestamp: 10)
    motion.relocate(from: .zero, to: CGPoint(x: 100, y: 0), timestamp: 20)
    motion.observe(at: CGPoint(x: 40, y: 0), timestamp: 25)
    #expect(motion.destination == CGPoint(x: -60, y: 0))
}

@Test func largeRealMotionIsNotDiscardedAndStaleSamplesAreIgnored() {
    var motion = StatusPointerMotion(at: CGPoint(x: 1300, y: 100), timestamp: 100)
    motion.observe(at: CGPoint(x: -1000, y: 200), timestamp: 110)
    #expect(motion.destination == CGPoint(x: -1000, y: 200))
    motion.observe(at: CGPoint(x: 1200, y: 50), timestamp: 90)
    #expect(motion.destination == CGPoint(x: -1000, y: 200))
}

@Test func offscreenInjectionUsesClampedDesktopPosition() {
    let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                   CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
    #expect(StatusPointerMotion.desktopPoint(CGPoint(x: -4000, y: 15), displays: screens) == CGPoint(x: -1920, y: 15))
    #expect(StatusPointerMotion.desktopPoint(CGPoint(x: 1400, y: 15), displays: screens) == CGPoint(x: 1400, y: 15))
}

@Test func restoreSnapshotIncludesMovementWhoseEventIsStillQueued() {
    var motion = StatusPointerMotion(at: CGPoint(x: 1400, y: 15), timestamp: 10)
    motion.relocate(from: CGPoint(x: 1400, y: 15), to: CGPoint(x: -1920, y: 15), timestamp: 20)
    motion.observe(at: CGPoint(x: -1917, y: 16), timestamp: 30)
    // The hardware position moved again before the main-loop callback ran.
    motion.observe(at: CGPoint(x: -1910, y: 18), timestamp: 40)
    #expect(motion.destination == CGPoint(x: 1410, y: 18))
    motion.observe(at: CGPoint(x: -1912, y: 17), timestamp: 35)
    #expect(motion.destination == CGPoint(x: 1410, y: 18))
}
