import CoreGraphics

/// Preserve the grab offset if AppKit stops exposing drag items at teardown.
/// Never reuse an absolute image frame from an earlier cursor position.
public struct StatusDragImage {
    private var offset: CGRect?
    public init() {}

    public mutating func observe(frame: CGRect, pointer: CGPoint) {
        guard !frame.isEmpty else { return }
        offset = frame.offsetBy(dx: -pointer.x, dy: -pointer.y)
    }

    public func frame(at pointer: CGPoint) -> CGRect? {
        offset?.offsetBy(dx: pointer.x, dy: pointer.y)
    }
}
