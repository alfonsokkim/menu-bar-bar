import CoreGraphics
import Testing
@testable import TrayCore

private let stableSource = CGRect(x: -4044, y: 0, width: 44, height: 30)
private let stableTarget = CGRect(x: -4000, y: 0, width: 5000, height: 30)

@Test func nativeMoveNeedsTwoConsecutiveSettledFrames() {
    var tracker = StatusMoveSettlement()
    let sample1 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(!sample1)
    let sample2 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(sample2)
}

@Test func invalidSamplesResetNativeSettlement() {
    for invalid in [CGRect?.none, stableSource.offsetBy(dx: 0, dy: 15)] {
        var tracker = StatusMoveSettlement()
        let sample3 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
        #expect(!sample3)
        let sample4 = tracker.observe(source: invalid, target: stableTarget, ownersMatch: true)
        #expect(!sample4)
        let sample5 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
        #expect(!sample5)
        let sample6 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
        #expect(sample6)
    }
}

@Test func targetMovementAndOwnerChangesResetSettlement() {
    var tracker = StatusMoveSettlement()
    let sample7 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(!sample7)
    let sample8 = tracker.observe(source: stableSource, target: stableTarget.offsetBy(dx: 44, dy: 0), ownersMatch: true)
    #expect(!sample8)
    let sample9 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: false)
    #expect(!sample9)
    let sample10 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(!sample10)
    let sample11 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(sample11)
}

@Test func stationaryWrongPlacementReleasesCursorButStillFailsPlacement() {
    var tracker = StatusMoveSettlement()
    let sample12 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(!sample12)
    let sample13 = tracker.observe(source: stableSource, target: stableTarget, ownersMatch: true)
    #expect(sample13)
    #expect(!StatusDragGeometry.isBeside(source: stableSource, target: stableTarget, onLeft: false))
}
