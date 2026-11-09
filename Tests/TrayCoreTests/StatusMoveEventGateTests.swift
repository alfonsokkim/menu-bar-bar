import CoreGraphics
import Testing
@testable import TrayCore

@Test func moveEventGateNeverForwardsKeyboardInput() {
    var gate = StatusMoveEventGate()
    gate.expect(type: .keyDown, token: 42, window: 12)
    gate.expect(type: .leftMouseDown, token: 42, window: 12)
    for type in [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDragged, .rightMouseDown] {
        let allowed = gate.consume(type: type, token: 42, window: 12)
        #expect(!allowed)
    }
    let mouseAllowed = gate.consume(type: .leftMouseDown, token: 42, window: 12)
    #expect(mouseAllowed)
}

@Test func moveEventGateForwardsOnlyOneMatchingMouseEvent() {
    var gate = StatusMoveEventGate()
    gate.expect(type: .leftMouseDown, token: 42, window: 12)
    let wrongToken = gate.consume(type: .leftMouseDown, token: 43, window: 12)
    let wrongWindow = gate.consume(type: .leftMouseDown, token: 42, window: 13)
    let wrongType = gate.consume(type: .leftMouseUp, token: 42, window: 12)
    let first = gate.consume(type: .leftMouseDown, token: 42, window: 12)
    let repeated = gate.consume(type: .leftMouseDown, token: 42, window: 12)
    #expect(!wrongToken && !wrongWindow && !wrongType)
    #expect(first)
    #expect(!repeated)
}
