import CoreGraphics
import Testing
@testable import TrayCore

@Test func commandDragRequiresMovement() {
    #expect(!StatusDragGeometry.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
    #expect(StatusDragGeometry.isDrag(from: .zero, to: CGPoint(x: 4, y: 0)))
}

@Test func shelfDropsMustLandInTheMenuBarOutsideTheBundleTrigger() {
    let bar = CGRect(x: -1920, y: -1080, width: 1920, height: 30)
    let trigger = CGRect(x: -300, y: -1080, width: 44, height: 30)
    #expect(StatusDragGeometry.isMenuBarDrop(CGPoint(x: -200, y: -1065), bar: bar, trigger: trigger))
    #expect(!StatusDragGeometry.isMenuBarDrop(CGPoint(x: -200, y: -1035), bar: bar, trigger: trigger))
    #expect(!StatusDragGeometry.isMenuBarDrop(CGPoint(x: -280, y: -1065), bar: bar, trigger: trigger))
    #expect(!StatusDragGeometry.isMenuBarDrop(CGPoint(x: 200, y: 15), bar: bar, trigger: trigger))
}

@Test func relocationVerificationRejectsOtherMenuBarRows() {
    let target = CGRect(x: 1000, y: 0, width: 44, height: 30)
    #expect(!StatusDragGeometry.isBeside(source: CGRect(x: -4000, y: 0, width: 44, height: 30), target: target, onLeft: true))
    #expect(StatusDragGeometry.isBeside(source: CGRect(x: 956, y: 0, width: 44, height: 30), target: target, onLeft: true))
    #expect(!StatusDragGeometry.isBeside(source: CGRect(x: -4000, y: -62, width: 44, height: 30), target: target, onLeft: true))
    #expect(!StatusDragGeometry.isBeside(source: CGRect(x: 990, y: 0, width: 44, height: 30), target: target, onLeft: true))
    #expect(StatusDragGeometry.isBeside(source: CGRect(x: 1044, y: 0, width: 44, height: 30), target: target, onLeft: false))
}

@Test func pointerInBarAcceptsAnIconMostlyAboveTheBar() {
    let bar = CGRect(x: 0, y: 0, width: 1920, height: 30)
    let trigger = CGRect(x: 1400, y: 0, width: 44, height: 30)
    let point = StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1500, y: 15),
        image: CGRect(x: 1480, y: -25, width: 40, height: 30), bar: bar, trigger: trigger)
    #expect(point == CGPoint(x: 1500, y: 15))
}

@Test func imageOverlapAcceptsPointerAboveOrBelowMenuBar() {
    let bar = CGRect(x: -1920, y: -1080, width: 1920, height: 30)
    let trigger = CGRect(x: -300, y: -1080, width: 44, height: 30)
    for (cursorY, imageY) in [(-1085.0, -1090.0), (-1040.0, -1065.0)] {
        let point = StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: -200, y: cursorY),
            image: CGRect(x: -220, y: imageY, width: 40, height: 30), bar: bar, trigger: trigger)
        #expect(point == CGPoint(x: -200, y: -1065))
    }
}

@Test func iconOverlapRejectsGrazingDesktopAndTriggerDrops() {
    let bar = CGRect(x: 0, y: 0, width: 1920, height: 30)
    let trigger = CGRect(x: 1400, y: 0, width: 44, height: 30)
    for frame in [CGRect(x: 1480, y: 29, width: 40, height: 30),
                  CGRect(x: 1480, y: 80, width: 40, height: 30),
                  CGRect(x: 1402, y: 15, width: 40, height: 30),
                  CGRect(x: -45, y: 0, width: 40, height: 30)] {
        #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: frame.midX, y: 45),
            image: frame, bar: bar, trigger: trigger) == nil)
    }
}

@Test func menuBarBoundaryAndWideIconsKeepPointerIntent() {
    let bar = CGRect(x: 0, y: 0, width: 1920, height: 30)
    let trigger = CGRect(x: 1400, y: 0, width: 44, height: 30)
    #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1500, y: 30),
        image: CGRect(x: 1400, y: 15, width: 138, height: 30), bar: bar, trigger: trigger) == CGPoint(x: 1500, y: 15))
    #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1420, y: 15),
        image: CGRect(x: 1470, y: 15, width: 138, height: 30), bar: bar, trigger: trigger) == nil)
}

@Test func nativeReleaseAlignsTheIconInsteadOfItsGrabPoint() throws {
    let target = CGRect(x: 1000, y: 0, width: 44, height: 30)
    let dragged = CGRect(x: 1200, y: 15, width: 44, height: 30)
    let y = try #require(StatusDragGeometry.releaseY(grabPoint: CGPoint(x: 1200, y: 15), draggedFrame: dragged, target: target))
    #expect(y == 0)
    #expect(dragged.midY + y - 15 == target.midY)
    #expect(StatusDragGeometry.releaseY(grabPoint: CGPoint(x: 1222, y: 30), draggedFrame: dragged, target: target) == 15)
    #expect(StatusDragGeometry.releaseY(grabPoint: CGPoint(x: 1222, y: 70), draggedFrame: dragged, target: target) == nil)
}

@Test func horizontalShelfReorderDoesNotBecomeAnOutboundDropFromASmallWobble() {
    let bar = CGRect(x: 0, y: 0, width: 1920, height: 30)
    let shelf = CGRect(x: 1300, y: 30, width: 300, height: 30)
    let trigger = CGRect(x: 1400, y: 0, width: 44, height: 30)
    #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1500, y: 41),
        image: CGRect(x: 1480, y: 26, width: 40, height: 30), bar: bar, trigger: trigger, shelf: shelf) == nil)
    #expect(StatusDragGeometry.menuBarDropPoint(pointer: CGPoint(x: 1500, y: 34),
        image: CGRect(x: 1480, y: 12, width: 40, height: 30), bar: bar, trigger: trigger, shelf: shelf) == CGPoint(x: 1500, y: 15))
}

private let reorderViewport = CGRect(x: 22, y: 1, width: 146, height: 30)
private let reorderCells = [
    ShelfDragCell(id: 1, frame: CGRect(x: 22, y: 1, width: 38, height: 30)),
    ShelfDragCell(id: 2, frame: CGRect(x: 60, y: 1, width: 64, height: 30)),
    ShelfDragCell(id: 3, frame: CGRect(x: 124, y: 1, width: 44, height: 30))
]

@Test func shelfReorderUsesNativeWidthsAndBothEnds() throws {
    let first = try #require(StatusDragGeometry.reorderSlot(for: 3, at: CGPoint(x: 23, y: 16),
                                                          viewport: reorderViewport, cells: reorderCells))
    #expect(first.targetID == 1 && first.onLeft && first.indicatorX == 22)
    let last = try #require(StatusDragGeometry.reorderSlot(for: 1, at: CGPoint(x: 167, y: 16),
                                                         viewport: reorderViewport, cells: reorderCells))
    #expect(last.targetID == 3 && !last.onLeft && last.indicatorX == 168)
    let middle = try #require(StatusDragGeometry.reorderSlot(for: 3, at: CGPoint(x: 90, y: 16),
                                                           viewport: reorderViewport, cells: reorderCells))
    #expect(middle.targetID == 2 && middle.onLeft && middle.indicatorX == 60)
}

@Test func shelfReorderExcludesTheDraggedIconAndPreservesItsOriginalSlot() throws {
    let slot = try #require(StatusDragGeometry.reorderSlot(for: 2, at: CGPoint(x: 92, y: 16),
                                                         viewport: reorderViewport, cells: reorderCells))
    #expect(slot.targetID == 3 && slot.onLeft)
    #expect(StatusDragGeometry.isBeside(source: reorderCells[1].frame,
                                       target: reorderCells[2].frame, onLeft: slot.onLeft))
}

@Test func shelfReorderRejectsOutsideDropsAndMissingSources() {
    for point in [CGPoint(x: 20, y: 16), CGPoint(x: 60, y: 0), CGPoint(x: 60, y: 32)] {
        #expect(StatusDragGeometry.reorderSlot(for: 1, at: point, viewport: reorderViewport, cells: reorderCells) == nil)
    }
    #expect(StatusDragGeometry.reorderSlot(for: 99, at: CGPoint(x: 60, y: 16), viewport: reorderViewport, cells: reorderCells) == nil)
    #expect(StatusDragGeometry.reorderSlot(for: 1, at: CGPoint(x: 30, y: 16), viewport: reorderViewport, cells: [reorderCells[0]]) == nil)
}

@Test func shelfReorderUsesVisibleCellsInAScrolledRow() throws {
    let cells = [ShelfDragCell(id: 1, frame: CGRect(x: -50, y: 1, width: 38, height: 30)),
                 ShelfDragCell(id: 2, frame: CGRect(x: 10, y: 1, width: 64, height: 30)),
                 ShelfDragCell(id: 3, frame: CGRect(x: 74, y: 1, width: 44, height: 30))]
    let slot = try #require(StatusDragGeometry.reorderSlot(for: 3, at: CGPoint(x: 23, y: 16),
                                                         viewport: reorderViewport, cells: cells))
    #expect(slot.targetID == 2 && slot.onLeft && slot.indicatorX == reorderViewport.minX)
}

@Test(arguments: [38.0, 44.0, 138.0])
func nativeReleasePlacesTheWholeIconOnTheRequestedSide(width: Double) throws {
    let dragged = CGRect(x: 1200, y: 15, width: width, height: 30)
    let target = CGRect(x: 1300, y: 0, width: 44, height: 30)
    for offset in [0.0, width / 2, width] {
        let grab = CGPoint(x: dragged.minX + offset, y: 15)
        for onLeft in [true, false] {
            let release = try #require(StatusDragGeometry.releasePoint(grabPoint: grab, draggedFrame: dragged,
                                                                         target: target, onLeft: onLeft))
            let placed = CGRect(x: release.x - offset, y: release.y, width: width, height: 30)
            #expect(StatusDragGeometry.isBeside(source: placed, target: target, onLeft: onLeft))
        }
    }
}

@Test func leftReleaseSupportsAnotherDisplayAndHiddenDividerCoordinates() throws {
    let dragged = CGRect(x: -600, y: 15, width: 44, height: 30)
    let target = CGRect(x: -5400, y: 0, width: 5000, height: 30)
    let release = try #require(StatusDragGeometry.releasePoint(grabPoint: CGPoint(x: -600, y: 15),
                                                              draggedFrame: dragged, target: target, onLeft: true))
    #expect(release == CGPoint(x: -5444, y: 0))
}

@Test func nativeReleaseRejectsHorizontalGrabOutsideTheIcon() {
    let dragged = CGRect(x: 1200, y: 15, width: 44, height: 30)
    let target = CGRect(x: 1300, y: 0, width: 44, height: 30)
    for x in [1198.0, 1246.0] {
        #expect(StatusDragGeometry.releasePoint(grabPoint: CGPoint(x: x, y: 15), draggedFrame: dragged,
                                                target: target, onLeft: true) == nil)
    }
}
