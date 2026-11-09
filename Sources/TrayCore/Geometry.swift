import Foundation
import CoreGraphics

public enum TrayGeometry {
    public static func belongsInTray(item: CGRect, divider: CGRect) -> Bool {
        abs(item.minY - divider.minY) < 2 && item.width > 0 &&
        item.height >= 16 && item.height <= 64 && item.maxX <= divider.minX + 1
    }

    public static func panelOrigin(anchor: CGRect, screen: CGRect, size: CGSize) -> CGPoint {
        let maximumX = max(screen.minX + 8, screen.maxX - size.width - 8)
        let x = min(maximumX, max(screen.minX + 8, anchor.midX - size.width / 2))
        return CGPoint(x: x, y: anchor.minY - size.height)
    }
}
