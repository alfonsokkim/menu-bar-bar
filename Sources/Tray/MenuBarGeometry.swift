import AppKit

/// Reads native menu bar bounds independently of the shelf background.
enum MenuBarGeometry {
    struct Window {
        let id: CGWindowID
        let frame: CGRect
    }

    nonisolated static func statusArea(menuBar: CGRect, titles: [CGRect], targetBar: CGRect) -> CGRect? {
        guard menuBar == targetBar, !titles.isEmpty, menuBar.width > 0,
              titles.allSatisfy({ $0.width > 0 && $0.minX >= menuBar.minX && $0.maxX <= menuBar.maxX }),
              let end = titles.map(\.maxX).max() else { return nil }
        guard end > targetBar.minX, end < targetBar.maxX else { return nil }
        return CGRect(x: end, y: targetBar.minY,
                      width: targetBar.maxX - end, height: targetBar.height)
    }

    static func frame(for screen: NSScreen) -> CGRect? { window(for: screen)?.frame }

    static func window(for screen: NSScreen) -> Window? {
        guard let main = NSScreen.screens.first else { return nil }
        let display = CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY,
                             width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return window(in: windows, display: display)
    }

    static func window(in windows: [[String: Any]], display: CGRect) -> Window? {
        func rect(_ info: [String: Any]) -> CGRect? {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard let bar = windows.first(where: { info in
            guard (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = rect(info) else { return false }
            return abs(frame.minX - display.minX) < 2 && abs(frame.width - display.width) < 2 &&
                abs(frame.minY - display.minY) < 2 && frame.height >= 16 && frame.height <= 64
        }), let barFrame = rect(bar),
            let id = bar[kCGWindowNumber as String] as? CGWindowID else { return nil }
        return Window(id: id, frame: barFrame)
    }

}
