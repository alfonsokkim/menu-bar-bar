import AppKit
import TrayCore
import ApplicationServices
import os

struct StatusWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let title: String

    static func all() -> [StatusWindow] {
        MenuItems.windowInfo().compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == Int(kCGStatusWindowLevel),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return StatusWindow(id: id, pid: pid, frame: frame, title: info[kCGWindowName as String] as? String ?? "")
        }
    }

    static func current(_ id: CGWindowID) -> StatusWindow? { all().first { $0.id == id } }
}

struct AvailableStatusItem: Identifiable {
    let window: StatusWindow
    let name: String
    var id: CGWindowID { window.id }
}

enum StatusItemMover {
    private static let eventPrefix: Int64 = 0x4D42_0000_0000_0000
    static func isMoveEvent(_ token: Int64) -> Bool { UInt64(bitPattern: token) >> 48 == 0x4D42 }

    enum Side { case left, right }
    enum Failure: LocalizedError {
        case unavailable, permission, didNotMove
        var errorDescription: String? {
            switch self {
            case .unavailable: "That menu bar item is no longer available."
            case .permission: "Enable Accessibility to move menu bar items."
            case .didNotMove: "Couldn’t confirm the icon’s final position. Check the bundle or use Arrange."
            }
        }
    }

    static func move(_ original: StatusWindow, beside target: StatusWindow, side: Side) async throws {
        guard AXIsProcessTrusted() else { throw Failure.permission }
        guard original.id != target.id,
              let item = StatusWindow.current(original.id), item.pid == original.pid,
              let destination = StatusWindow.current(target.id), destination.pid == target.pid,
              let source = CGEventSource(stateID: .privateState) else { throw Failure.unavailable }
        guard abs(item.frame.midY - destination.frame.midY) < 3 else { throw Failure.unavailable }
        try Task.checkCancellation()
        if StatusDragGeometry.isBeside(source: item.frame, target: destination.frame, onLeft: side == .left) { return }
        let pointer = StatusMovePointer()
        guard pointer.start() else { throw Failure.permission }
        defer { pointer.finish(resuming: source) }
        let delivery = StatusEventDelivery(pid: item.pid)
        guard delivery.start() else { throw Failure.permission }
        defer { delivery.stop() }
        let start = CGPoint(x: destination.frame.maxX - 1, y: destination.frame.midY)
        var end = CGPoint(x: side == .left ? destination.frame.minX : destination.frame.maxX,
                          y: destination.frame.midY)
        func event(_ type: CGEventType, at point: CGPoint, window: CGWindowID) -> CGEvent? {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return nil }
            event.flags = type == .leftMouseDown ? .maskCommand : []
            event.setIntegerValueField(.eventSourceUserData, value: eventPrefix | Int64.random(in: 0...0x0000_FFFF_FFFF_FFFF))
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
            // AppKit's hosted status windows use this window-routing field.
            if let field = CGEventField(rawValue: 0x33) { event.setIntegerValueField(field, value: Int64(window)) }
            return event
        }
        let rollbackPoint = CGPoint(x: item.frame.midX, y: item.frame.midY)
        guard let down = event(.leftMouseDown, at: start, window: item.id),
              let up = event(.leftMouseUp, at: end, window: destination.id),
              let cancel = event(.leftMouseUp, at: rollbackPoint, window: item.id) else { throw Failure.unavailable }
        let logger = Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove")
        var released = false
        guard pointer.hide() else { throw Failure.unavailable }
        do {
            delivery.expect(down)
            try pointer.post(down)
            let (liveSource, liveTarget, grabPoint) = try await grabbed(item: item, target: destination,
                                                                       down: down, delivery: delivery)
            logger.notice("Move host geometry: source y=\(liveSource.frame.midY), target y=\(liveTarget.frame.midY), original target y=\(destination.frame.midY)")
            // A grabbed source can temporarily leave its normal row. Validate the
            // destination against the original row, then verify both after release.
            guard abs(liveTarget.frame.midY - destination.frame.midY) < 3 else { throw Failure.unavailable }
            guard let releasePoint = StatusDragGeometry.releasePoint(grabPoint: grabPoint, draggedFrame: liveSource.frame,
                                                                      target: liveTarget.frame, onLeft: side == .left) else { throw Failure.didNotMove }
            end = releasePoint
            logger.notice("Native grab cursor y=\(grabPoint.y), icon center y=\(liveSource.frame.midY), release x=\(end.x) y=\(end.y)")
            logger.notice("Native horizontal grab cursor x=\(grabPoint.x), icon left=\(liveSource.frame.minX), width=\(liveSource.frame.width), target left=\(liveTarget.frame.minX), right=\(liveTarget.frame.maxX), wants left=\(side == .left)")
            up.location = end
            delivery.expect(up)
            try pointer.post(up)
            for _ in 0..<15 {
                try await Task.sleep(for: .milliseconds(10))
                if delivery.didForward(up) { released = true; break }
            }
            guard released else { throw Failure.didNotMove }
            // Receipt in the host stream is stronger than merely enqueueing
            // postToPid. Once our release and pointer rebase are both observed,
            // stop borrowing the cursor while the icon's visual layout settles.
            if delivery.observesHost {
                for _ in 0..<10 {
                    if delivery.didReceive(up), !pointer.hasPendingRelocations {
                        pointer.finish(resuming: source)
                        break
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
        } catch {
            if !delivery.didForward(up) {
                // Balance WindowServer's mouse-down before restoring the cursor.
                // The session release stays onscreen even if delivery is late;
                // only its one-shot host copy uses the logical rollback slot.
                cancel.location = pointer.destination
                delivery.expect(cancel, hostLocation: rollbackPoint)
                try? pointer.post(cancel)
                await Task { @MainActor in
                    for _ in 0..<15 {
                        if delivery.didForward(cancel) { break }
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                }.value
            }
            // A canceled caller must still let queued mouse events settle.
            // This task deliberately does not inherit caller cancellation.
            _ = await Task { @MainActor in
                await settled(item: item, target: destination, side: nil)
            }.value
            throw error
        }
        delivery.stop()
        let succeeded = await Task { @MainActor in
            await settled(item: item, target: destination, side: side)
        }.value
        try Task.checkCancellation()
        if succeeded { return }
        throw Failure.didNotMove
    }

    private static func grabbed(item: StatusWindow, target: StatusWindow, down: CGEvent,
                                delivery: StatusEventDelivery) async throws -> (StatusWindow, StatusWindow, CGPoint) {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(150))
        repeat {
            try await Task.sleep(for: .milliseconds(5))
            guard delivery.didForward(down), !delivery.observesHost || delivery.didReceive(down) else { continue }
            let windows = StatusWindow.all()
            guard let source = windows.first(where: { $0.id == item.id }), source.pid == item.pid,
                  let destination = windows.first(where: { $0.id == target.id }), destination.pid == target.pid,
                  abs(destination.frame.midY - target.frame.midY) < 3,
                  let point = CGEvent(source: nil)?.location else { throw Failure.unavailable }
            if source.frame.origin != item.frame.origin,
               source.frame.insetBy(dx: -2, dy: -2).contains(point) {
                return (source, destination, point)
            }
        } while ContinuousClock.now < deadline
        throw Failure.didNotMove
    }

    private static func settled(item: StatusWindow, target: StatusWindow, side: Side?) async -> Bool {
        var tracker = StatusMoveSettlement()
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(40))
            // Read both frames from one snapshot, avoiding duplicate synchronous
            // WindowServer work and comparisons from different layout moments.
            let windows = StatusWindow.all()
            let current = windows.first { $0.id == item.id }
            let destination = windows.first { $0.id == target.id }
            if tracker.observe(source: current?.frame, target: destination?.frame,
                               ownersMatch: current?.pid == item.pid && destination?.pid == target.pid) {
                // Once both windows stop moving, cursor control can end.
                // A stationary icon in the wrong slot is a placement failure,
                // not a reason to keep the cursor hidden until the timeout.
                guard let side else { return true }
                guard let current, let destination else { return false }
                return StatusDragGeometry.isBeside(source: current.frame, target: destination.frame,
                                                  onLeft: side == .left)
            }
        }
        return false
    }
}


/// Route only our marked status-item events to their hosting process after
/// WindowServer has seen them. All physical input passes through unchanged.
private final class StatusEventDelivery {
    let pid: pid_t
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = StatusMoveEventGate()
    private var forwarded: Set<Int64> = []
    private var hostLocations: [Int64: CGPoint] = [:]
    private var hostTap: CFMachPort?
    private var hostSource: CFRunLoopSource?
    private var hostGate = StatusMoveEventGate()
    private var received: Set<Int64> = []
    var observesHost: Bool { hostTap != nil }

    init(pid: pid_t) { self.pid = pid }

    func expect(_ event: CGEvent, hostLocation: CGPoint? = nil) {
        hostGate.expect(type: event.type, token: event.getIntegerValueField(.eventSourceUserData), window: 0)
        if let hostLocation { hostLocations[event.getIntegerValueField(.eventSourceUserData)] = hostLocation }
        gate.expect(type: event.type, token: event.getIntegerValueField(.eventSourceUserData),
                    window: UInt32(clamping: event.getIntegerValueField(.mouseEventWindowUnderMousePointer)))
    }

    func didForward(_ event: CGEvent) -> Bool {
        forwarded.contains(event.getIntegerValueField(.eventSourceUserData))
    }

    func didReceive(_ event: CGEvent) -> Bool {
        received.contains(event.getIntegerValueField(.eventSourceUserData))
    }

    func start() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .listenOnly, eventsOfInterest: mask,
                                         callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                let delivery = Unmanaged<StatusEventDelivery>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = delivery.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if event.type == type, delivery.gate.consume(type: type,
                    token: event.getIntegerValueField(.eventSourceUserData),
                    window: UInt32(clamping: event.getIntegerValueField(.mouseEventWindowUnderMousePointer))) {
                    if let copy = event.copy() {
                        if let location = delivery.hostLocations.removeValue(forKey: event.getIntegerValueField(.eventSourceUserData)) {
                            copy.location = location
                        }
                        let originalToken = event.getIntegerValueField(.eventSourceUserData)
                        copy.postToPid(delivery.pid)
                        delivery.forwarded.insert(originalToken)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        startHostObservation(mask: mask)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func startHostObservation(mask: CGEventMask) {
        guard let tap = CGEvent.tapCreateForPid(pid: pid, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let delivery = Unmanaged<StatusEventDelivery>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = delivery.hostTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if event.type == type {
                        let token = event.getIntegerValueField(.eventSourceUserData)
                        if StatusItemMover.isMoveEvent(token) {
                            Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove")
                                .notice("Host tap observed type=\(type.rawValue) token=\(token) window=\(event.getIntegerValueField(.mouseEventWindowUnderMousePointer))")
                        }
                        // Host annotations rewrite the window field. Match
                        // only our registered token/type inside this PID.
                        if delivery.hostGate.consume(type: type, token: token, window: 0) {
                            delivery.received.insert(token)
                            Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove")
                                .notice("Host received marked mouse event type=\(type.rawValue)")
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove").notice("Host observation unavailable pid=\(self.pid)")
            return
        }
        Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove").notice("Host observation enabled pid=\(self.pid)")
        hostTap = tap
        hostSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let hostTap { CGEvent.tapEnable(tap: hostTap, enable: false); CFMachPortInvalidate(hostTap) }
        if let hostSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), hostSource, .commonModes) }
        hostTap = nil
        hostSource = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}
