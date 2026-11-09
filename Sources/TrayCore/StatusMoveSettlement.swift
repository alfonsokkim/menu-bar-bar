import CoreGraphics

/// Require two consecutive valid observations of both native windows.
/// Stability releases cursor control even when the requested placement failed.
public struct StatusMoveSettlement {
    private var sourceFrame: CGRect?
    private var targetFrame: CGRect?
    public init() {}

    public mutating func observe(source: CGRect?, target: CGRect?, ownersMatch: Bool) -> Bool {
        guard let source, let target, ownersMatch, abs(source.midY - target.midY) < 3 else {
            sourceFrame = nil
            targetFrame = nil
            return false
        }
        let stable = sourceFrame == source && targetFrame == target
        sourceFrame = source
        targetFrame = target
        return stable
    }
}
