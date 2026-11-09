import AppKit
import os

/// Cursor hiding normally applies only to the foreground app. Native status
/// drags leave this accessory app in the background, so scope background
/// cursor control to the move and balance it before releasing the connection.
final class StatusCursorVisibility {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFBoolean) -> CGError
    private typealias IsVisible = @convention(c) () -> UInt32
    private var connection: Int32?
    private var setProperty: SetProperty?
    private var hidden = false
    private let identifier = UUID().uuidString.prefix(8)
    private let logger = Logger(subsystem: "com.alfonsokim.tray", category: "StatusPointer")

    static var isVisible: Bool? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else { return nil }
        return unsafeBitCast(symbol, to: IsVisible.self)() != 0
    }

    func hide() -> Bool {
        guard !hidden else { return true }
        record("before hide")
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let propertySymbol = dlsym(handle, "CGSSetConnectionProperty") else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
        guard setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == .success else { return false }
        self.connection = connection
        self.setProperty = setProperty
        hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
        let visible = Self.isVisible
        Logger(subsystem: "com.alfonsokim.tray", category: "StatusPointer")
            .notice("Cursor hide: app active=\(NSApp.isActive), hidden=\(self.hidden), visible=\(String(describing: visible), privacy: .public)")
        guard hidden, visible == false else {
            show()
            return false
        }
        return true
    }

    func show() {
        if hidden {
            let result = CGDisplayShowCursor(CGMainDisplayID())
            logger.notice("Cursor show result=\(result.rawValue) id=\(self.identifier, privacy: .public)")
            record("after show")
            if result != .success {
                Logger(subsystem: "com.alfonsokim.tray", category: "StatusPointer")
                    .error("Could not show cursor: \(result.rawValue)")
            }
            hidden = false
        }
        if let connection, let setProperty {
            let result = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanFalse)
            if result != .success {
                Logger(subsystem: "com.alfonsokim.tray", category: "StatusPointer")
                    .error("Could not reset background cursor control: \(result.rawValue)")
            }
        }
        connection = nil
        setProperty = nil
        record("after reset")
        Task { @MainActor [self] in
            await Task.yield()
            record("next turn")
            try? await Task.sleep(for: .milliseconds(50))
            record("after 50ms")
            try? await Task.sleep(for: .milliseconds(150))
            record("after 200ms")
            try? await Task.sleep(for: .milliseconds(800))
            record("after 1s")
        }
    }

    private func record(_ stage: String) {
        let point = CGEvent(source: nil)?.location ?? .zero
        let cursor = NSCursor.currentSystem
        logger.notice("Cursor visibility id=\(self.identifier, privacy: .public) stage=\(stage, privacy: .public) visible=\(String(describing: Self.isVisible), privacy: .public) active=\(NSApp.isActive) x=\(point.x) y=\(point.y) cursor=\(String(describing: cursor), privacy: .public)")
    }
}
