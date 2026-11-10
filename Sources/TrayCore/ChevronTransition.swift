import CoreGraphics
import Foundation

/// The visible part of the gravity trajectory. Read its phase only when a
/// transition is interrupted; SwiftUI owns frame-by-frame interpolation.
public struct ChevronTransition {
    public let start: CGFloat
    public let target: CGFloat
    public let began: TimeInterval
    public let duration: TimeInterval

    public init(opening: Bool, phase: CGFloat, began: TimeInterval) {
        start = min(0.6, max(0, phase))
        target = opening ? 0.6 : 0
        self.began = began
        duration = max(0.001, 0.22 * Double(abs(target - start)))
    }

    public func phase(at time: TimeInterval) -> CGFloat {
        let elapsed = min(1, max(0, (time - began) / duration))
        return start + (target - start) * elapsed
    }
}
