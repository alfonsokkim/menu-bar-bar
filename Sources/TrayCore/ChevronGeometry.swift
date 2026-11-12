import CoreGraphics

public enum ChevronGeometry {
    /// Top-left coordinates. The two arms flatten at the midpoint and invert.
    public static func points(progress: CGFloat, center: CGPoint) -> [CGPoint] {
        let direction = 1 - 2 * min(1, max(0, progress))
        return [CGPoint(x: center.x - 4, y: center.y - 2 * direction),
                CGPoint(x: center.x, y: center.y + 2 * direction),
                CGPoint(x: center.x + 4, y: center.y - 2 * direction)]
    }
}
