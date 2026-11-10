import AppKit

/// Reads window bounds only. The shelf never captures or paints a background.
enum MenuBarGeometry {
    static func frame(for screen: NSScreen) -> CGRect? {
        guard let main = NSScreen.screens.first else { return nil }
        let display = CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY,
                             width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        func rect(_ info: [String: Any]) -> CGRect? {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard let bar = windows.first(where: { info in
            guard (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let frame = rect(info) else { return false }
            return abs(frame.minX - display.minX) < 2 && abs(frame.width - display.width) < 2 &&
                abs(frame.minY - display.minY) < 2 && frame.height >= 16 && frame.height <= 64
        }), let barFrame = rect(bar) else { return nil }
        return barFrame
    }

}
