import AppKit
import os
import TrayCore

/// Rebase cursor coordinates on our own generated events in the same stream
/// as physical mouse movement, without integrating poisoned Quartz deltas.
/// Restore after release delivery is acknowledged, or after native settlement
/// when the host cannot acknowledge its event stream.
final class StatusMovePointer {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var motion: StatusPointerMotion?
    var destination: CGPoint { motion?.destination ?? .zero }
    var hasPendingRelocations: Bool { !pendingRelocations.isEmpty }
    private var active = false
    private var hidden = false
    private let cursorVisibility = StatusCursorVisibility()
    private let logger = Logger(subsystem: "com.alfonsokim.tray", category: "StatusPointer")
    private var movementCount = 0
    private var pendingRelocations: [Int64: (before: CGPoint, after: CGPoint)] = [:]
    private var relocationGate = StatusMoveEventGate()

    func start() -> Bool {
        guard let point = CGEvent(source: nil)?.location else { return false }
        motion = StatusPointerMotion(at: point, timestamp: DispatchTime.now().uptimeNanoseconds)
        logger.notice("Pointer begin x=\(point.x) y=\(point.y)")
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .listenOnly, eventsOfInterest: mask,
                                         callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                let pointer = Unmanaged<StatusMovePointer>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = pointer.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if pointer.active, event.type == type {
                    let token = event.getIntegerValueField(.eventSourceUserData)
                    if pointer.relocationGate.consume(type: type, token: token,
                        window: UInt32(clamping: event.getIntegerValueField(.mouseEventWindowUnderMousePointer))),
                       let relocation = pointer.pendingRelocations.removeValue(forKey: token) {
                        pointer.motion?.relocate(from: relocation.before, to: relocation.after, timestamp: event.timestamp)
                        let actual = CGEvent(source: nil)?.location ?? event.location
                        pointer.logger.notice("Rebased cursor x=\(relocation.after.x) y=\(relocation.after.y) actual x=\(actual.x) y=\(actual.y) time=\(event.timestamp)")
                    } else if !StatusItemMover.isMoveEvent(token) {
                        pointer.motion?.observe(at: event.location, timestamp: event.timestamp)
                        if pointer.movementCount < 30 {
                            pointer.logger.notice("Motion x=\(event.location.x) y=\(event.location.y) raw dx=\(event.getDoubleValueField(.mouseEventDeltaX)) raw dy=\(event.getDoubleValueField(.mouseEventDeltaY)) tracked x=\(pointer.destination.x) y=\(pointer.destination.y) time=\(event.timestamp)")
                        }
                        pointer.movementCount += 1
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        active = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func hide() -> Bool {
        hidden = cursorVisibility.hide()
        return hidden
    }

    func post(_ event: CGEvent) throws {
        guard let before = CGEvent(source: nil)?.location else { throw StatusItemMover.Failure.unavailable }
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return CGDisplayBounds(id)
        }
        let after = StatusPointerMotion.desktopPoint(event.location, displays: displays)
        let time = DispatchTime.now().uptimeNanoseconds
        event.timestamp = time
        pendingRelocations[event.getIntegerValueField(.eventSourceUserData)] = (before, after)
        relocationGate.expect(type: event.type, token: event.getIntegerValueField(.eventSourceUserData),
                              window: UInt32(clamping: event.getIntegerValueField(.mouseEventWindowUnderMousePointer)))
        logger.notice("Cursor relocation from x=\(before.x) y=\(before.y) to x=\(after.x) y=\(after.y) time=\(time)")
        event.post(tap: .cgSessionEventTap)
    }

    func finish(resuming eventSource: CGEventSource) {
        guard active else { return }
        // Include physical motion already applied by WindowServer whose event
        // callback is still queued. Never sample across an unobserved rebase.
        if hidden, pendingRelocations.isEmpty, let current = CGEvent(source: nil)?.location {
            motion?.observe(at: current, timestamp: DispatchTime.now().uptimeNanoseconds)
        }
        active = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if hidden {
            logger.notice("Pointer restore x=\(self.destination.x) y=\(self.destination.y) samples=\(self.movementCount)")
            let restored = CGWarpMouseCursorPosition(destination) == .success
            cursorVisibility.show()
            hidden = false
            // The move source otherwise leaves a 250ms hardware-input pause.
            // Change its policy only after the borrowed pointer is back, then
            // submit it without another mouse or key action.
            if restored {
                let localEvents: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
                eventSource.localEventsSuppressionInterval = 0
                eventSource.setLocalEventsFilterDuringSuppressionState(localEvents, state: .eventSuppressionStateSuppressionInterval)
                eventSource.setLocalEventsFilterDuringSuppressionState(localEvents, state: .eventSuppressionStateRemoteMouseDrag)
                if let resume = CGEvent(source: eventSource) {
                    resume.type = .null
                    resume.location = CGEvent(source: nil)?.location ?? destination
                    resume.flags = CGEventSource.flagsState(.hidSystemState)
                    resume.post(tap: .cgSessionEventTap)
                    logger.notice("Posted input-resume marker after cursor restoration")
                }
            }
        }
    }
}
