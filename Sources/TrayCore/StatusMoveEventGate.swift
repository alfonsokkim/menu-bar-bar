import CoreGraphics

/// Each generated mouse event may be forwarded once. Keyboard events and
/// unregistered events never pass, even if their metadata happens to match.
public struct StatusMoveEventGate {
    private var expected: [UInt32: (token: Int64, window: UInt32)] = [:]
    public init() {}

    public mutating func expect(type: CGEventType, token: Int64, window: UInt32) {
        guard type == .leftMouseDown || type == .leftMouseUp else { return }
        expected[type.rawValue] = (token, window)
    }

    public mutating func consume(type: CGEventType, token: Int64, window: UInt32) -> Bool {
        guard type == .leftMouseDown || type == .leftMouseUp,
              let value = expected[type.rawValue], value.token == token, value.window == window else { return false }
        expected.removeValue(forKey: type.rawValue)
        return true
    }
}
