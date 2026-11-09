import CoreGraphics

/// Observe generated relocations and real mouse positions in one event stream.
/// Never integrate Quartz deltas, which can contain the app's own cursor jumps.
public struct StatusPointerMotion {
    public private(set) var destination: CGPoint
    private var previous: CGPoint
    private var lastTimestamp: UInt64

    public init(at point: CGPoint, timestamp: UInt64) {
        destination = point
        previous = point
        lastTimestamp = timestamp
    }

    public mutating func relocate(from before: CGPoint, to after: CGPoint, timestamp: UInt64) {
        // The pre-post snapshot includes physical movement whose older events
        // may still be queued. Account for it once, before changing coordinates.
        if timestamp >= lastTimestamp {
            destination.x += before.x - previous.x
            destination.y += before.y - previous.y
        }
        previous = after
        lastTimestamp = max(lastTimestamp, timestamp)
    }

    public mutating func observe(at point: CGPoint, timestamp: UInt64) {
        guard timestamp >= lastTimestamp else { return }
        destination.x += point.x - previous.x
        destination.y += point.y - previous.y
        previous = point
        lastTimestamp = timestamp
    }

    /// WindowServer clamps an offscreen generated event to the desktop.
    public static func desktopPoint(_ point: CGPoint, displays: [CGRect]) -> CGPoint {
        displays.map { bounds in
            CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX - 1),
                    y: min(max(point.y, bounds.minY), bounds.maxY - 1))
        }.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
    }
}
