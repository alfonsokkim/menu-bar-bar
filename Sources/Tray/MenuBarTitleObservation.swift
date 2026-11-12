import AppKit
import ApplicationServices

nonisolated enum MenuBarTitleEvent: Sendable, Equatable { case changed, unsupportedLayout }

nonisolated struct MenuBarTitleMeasurement: Sendable {
    let ownerPID: pid_t
    let menuBar: CGRect
    let titles: [CGRect]
    let observation: MenuBarTitleObservation
}

/// AX identities are immutable; callback queue state and delivery use the main
/// actor. Registration happens on the reader thread. Releasing the token stops
/// its worker and removes its source on the main actor, even after cancellation.
nonisolated final class MenuBarTitleObservation: @unchecked Sendable {
    // Retain a notification's CF handle while its read-only role query crosses
    // executors. No AppKit object or shared Swift state is transferred.
    struct EventElement: @unchecked Sendable { let value: AXUIElement }

    // AX identities and the reader are immutable. Queue/cache mutation and
    // notification delivery are confined to the main actor.
    final class Callback: @unchecked Sendable {
        let notify: @MainActor @Sendable (MenuBarTitleEvent) -> Void
        let app: AXUIElement
        let menu: AXUIElement
        let titles: [AXUIElement]
        private let roles = NSCache<AXUIElement, NSNumber>()
        private let classify: @Sendable (EventElement) async -> Bool?
        @MainActor private(set) var worker: Task<Void, Never>?
        @MainActor private var pending: [EventElement] = []
        @MainActor private var inFlight: AXUIElement?
        @MainActor private var stopped = false
        static let capacity = 64

        init(app: AXUIElement, menu: AXUIElement, titles: [AXUIElement],
             classify: @escaping @Sendable (EventElement) async -> Bool? = { await MenuBarTitleObservation.isMenuElement($0) },
             notify: @escaping @MainActor @Sendable (MenuBarTitleEvent) -> Void) {
            self.app = app
            self.menu = menu
            self.titles = titles
            self.notify = notify
            self.classify = classify
            roles.countLimit = 128
        }

        @MainActor func stop() {
            stopped = true
            pending.removeAll()
            worker?.cancel()
        }

        @MainActor func report(_ event: MenuBarTitleEvent) {
            guard !stopped else { return }
            stop()
            notify(event)
        }

        @MainActor func receive(_ elements: [AXUIElement], notification: CFString) {
            guard !stopped else { return }
            guard elements.count <= Self.capacity else { report(.unsupportedLayout); return }
            if elements.contains(where: { element in
                CFEqual(element, menu) || titles.contains(where: { CFEqual($0, element) })
            }) {
                report(.changed)
                return
            }
            let destroyed = CFEqual(notification, kAXUIElementDestroyedNotification as CFString)
            let created = CFEqual(notification, kAXCreatedNotification as CFString)
            for element in elements {
                if destroyed || created {
                    roles.removeObject(forKey: element)
                    // Never let a read of an old identity populate a new cache entry.
                    if let inFlight, CFEqual(inFlight, element) { report(.changed); return }
                    pending.removeAll { CFEqual($0.value, element) }
                }
                if destroyed { continue }
                if let cached = roles.object(forKey: element) {
                    if cached.boolValue { report(.changed); return }
                } else if inFlight.map({ CFEqual($0, element) }) != true &&
                            !pending.contains(where: { CFEqual($0.value, element) }) {
                    guard pending.count + (inFlight == nil ? 0 : 1) < Self.capacity else {
                        report(.unsupportedLayout)
                        return
                    }
                    pending.append(EventElement(value: element))
                }
            }
            guard worker == nil, !pending.isEmpty else { return }
            worker = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.worker = nil; self.inFlight = nil }
                let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
                while !self.pending.isEmpty {
                    guard !Task.isCancelled, !self.stopped else { return }
                    guard ContinuousClock.now < deadline else { self.report(.unsupportedLayout); return }
                    let event = self.pending.removeFirst()
                    self.inFlight = event.value
                    let relevant = await self.classify(event)
                    self.inFlight = nil
                    guard !Task.isCancelled, !self.stopped else { return }
                    if let relevant { self.roles.setObject(NSNumber(value: relevant), forKey: event.value) }
                    if relevant != false { self.report(.changed); return }
                }
            }
        }
    }

    private let observer: AXObserver
    private let callback: Callback

    private init(observer: AXObserver, callback: Callback) {
        self.observer = observer
        self.callback = callback
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    deinit {
        let observer = observer
        let callback = callback
        Task { @MainActor in
            // A failed background read can release the token while a callback
            // is running. Keep its context alive through main-thread removal.
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            callback.stop()
            withExtendedLifetime(callback) { }
        }
    }

    @concurrent static func measure(ownerPID: pid_t,
        onEvent: @escaping @MainActor @Sendable (MenuBarTitleEvent) -> Void) async -> MenuBarTitleMeasurement? {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        func isCurrent() -> Bool { !Task.isCancelled && ContinuousClock.now < deadline }
        let app = AXUIElementCreateApplication(ownerPID)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var menuValue: CFTypeRef?
        guard isCurrent(),
              AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuValue) == .success,
              let menuValue, CFGetTypeID(menuValue) == AXUIElementGetTypeID() else { return nil }
        let menu = unsafeDowncast(menuValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(menu, 0.05)
        var childrenValue: CFTypeRef?
        guard isCurrent(),
              AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        let callback = Callback(app: app, menu: menu, titles: children, notify: onEvent)
        var observerValue: AXObserver?
        guard AXObserverCreateWithInfoCallback(ownerPID, { _, element, notification, info, context in
            guard let context else { return }
            let callback = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
            // Copy the immutable CF identities into Sendable wrappers before
            // entering the actor guaranteed by this source's main run loop.
            var affectedElements = [EventElement(value: element)]
            var unsupported = false
            if CFEqual(notification, kAXLayoutChangedNotification as CFString) {
                if let affected = (info as NSDictionary)[kAXUIElementsKey as String] as? [AXUIElement], !affected.isEmpty {
                    if affected.count >= Callback.capacity { unsupported = true }
                    else { affectedElements.append(contentsOf: affected.map { EventElement(value: $0) }) }
                } else if CFEqual(element, callback.app) { unsupported = true }
            }
            let elements = affectedElements
            let unsupportedLayout = unsupported
            let name = notification as String
            MainActor.assumeIsolated {
                if unsupportedLayout { callback.report(.unsupportedLayout) }
                else { callback.receive(elements.map(\.value), notification: name as CFString) }
            }
        }, &observerValue) == .success, let observer = observerValue else { return nil }
        let context = Unmanaged.passUnretained(callback).toOpaque()
        // Application-level subscriptions receive descendant notifications.
        // Menu-bar subscriptions alone miss changes posted by individual titles.
        // Unsupported observations fail closed rather than relying on polling.
        for notification in [kAXLayoutChangedNotification, kAXTitleChangedNotification, kAXCreatedNotification,
                             kAXUIElementDestroyedNotification, kAXResizedNotification, kAXMovedNotification] {
            guard isCurrent(), AXObserverAddNotification(observer, app, notification as CFString, context) == .success else { return nil }
        }
        let observation = MenuBarTitleObservation(observer: observer, callback: callback)
        return withExtendedLifetime(observation) {
            var currentChildrenValue: CFTypeRef?
            guard isCurrent(), let menuFrame = frame(menu),
                  AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &currentChildrenValue) == .success,
                  let currentChildren = currentChildrenValue as? [AXUIElement],
                  currentChildren.count == children.count,
                  zip(children, currentChildren).allSatisfy({ CFEqual($0, $1) }) else { return nil }
            var titles: [CGRect] = []
            for child in children {
                AXUIElementSetMessagingTimeout(child, 0.05)
                guard isCurrent(), let title = frame(child) else { return nil }
                titles.append(title)
            }
            guard isCurrent(), MenuBarGeometry.statusArea(menuBar: menuFrame, titles: titles, targetBar: menuFrame) != nil else { return nil }
            return MenuBarTitleMeasurement(ownerPID: ownerPID, menuBar: menuFrame, titles: titles, observation: observation)
        }
    }

    @concurrent private static func isMenuElement(_ event: EventElement) async -> Bool? {
        let element = event.value
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String else { return nil }
        return role == kAXMenuBarRole || role == kAXMenuBarItemRole
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
