import Foundation
import CoreGraphics
import Testing
@testable import TrayCore

@Test func selectsOnlyItemsLeftOfDividerOnSameDisplay() {
    let divider = CGRect(x: 600, y: 0, width: 18, height: 30)
    #expect(TrayGeometry.belongsInTray(item: CGRect(x: 560, y: 0, width: 28, height: 30), divider: divider))
    #expect(!TrayGeometry.belongsInTray(item: CGRect(x: 630, y: 0, width: 28, height: 30), divider: divider))
    #expect(!TrayGeometry.belongsInTray(item: CGRect(x: 560, y: 900, width: 28, height: 30), divider: divider))
    #expect(!TrayGeometry.belongsInTray(item: CGRect(x: 560, y: 0, width: 28, height: 200), divider: divider))
}

@Test func recognizesOffscreenHiddenItems() {
    let divider = CGRect(x: -9000, y: 0, width: 10000, height: 30)
    #expect(TrayGeometry.belongsInTray(item: CGRect(x: -9040, y: 0, width: 28, height: 30), divider: divider))
    #expect(!TrayGeometry.belongsInTray(item: CGRect(x: 1020, y: 0, width: 28, height: 30), divider: divider))
}

@Test func shelfStaysWithinScreenEdges() {
    let screen = CGRect(x: -1800, y: 0, width: 1800, height: 1100)
    let size = CGSize(width: 200, height: 46)
    let left = TrayGeometry.panelOrigin(anchor: CGRect(x: -1790, y: 1070, width: 24, height: 30), screen: screen, size: size)
    #expect(left.x == -1792)
    #expect(left.y == 1024)
    let right = TrayGeometry.panelOrigin(anchor: CGRect(x: -25, y: 1070, width: 24, height: 30), screen: screen, size: size)
    #expect(right.x == -208)
}
