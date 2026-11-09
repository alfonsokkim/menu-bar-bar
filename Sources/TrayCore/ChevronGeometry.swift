import CoreGraphics

public enum ChevronGeometry {
    public struct Stroke {
        public let start: CGPoint
        public let control: CGPoint
        public let end: CGPoint
    }

    public static func opacity(phase: CGFloat) -> CGFloat {
        min(1, max(0, (0.6 - phase) / 0.5))
    }

    public static func strokes(phase: CGFloat, center: CGPoint, travel: CGFloat) -> [Stroke] {
        let p = min(1, max(0, phase))
        // Released from rest under constant acceleration: distance = 1/2 a t².
        // Travel is the distance at normalized time 1, absorbing 1/2 a.
        let fall = p * p
        let y = center.y + travel * fall
        return [
            Stroke(start: CGPoint(x: center.x - 4, y: y - 2),
                   control: CGPoint(x: center.x - 2, y: y),
                   end: CGPoint(x: center.x, y: y + 2)),
            Stroke(start: CGPoint(x: center.x, y: y + 2),
                   control: CGPoint(x: center.x + 2, y: y),
                   end: CGPoint(x: center.x + 4, y: y - 2))
        ]
    }
}
