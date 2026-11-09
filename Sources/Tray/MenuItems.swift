import AppKit
import ApplicationServices
import ScreenCaptureKit
import TrayCore

struct MenuItem: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let sourcePID: pid_t
    let name: String
    let frame: CGRect
    let image: NSImage?
    let isLiveImage: Bool
    var orderKey: String = ""
}

nonisolated struct SourceApp: Sendable {
    let pid: pid_t
    let name: String
}

nonisolated struct SourceItem: Sendable {
    let pid: pid_t
    let name: String
    let frame: CGRect
}

enum MenuAccessibility {
    // AX messaging can block on another process. Keep it off the UI thread and
    // cap every target's timeout so an unresponsive app cannot stall the tray.
    @concurrent nonisolated static func scan(_ apps: [SourceApp]) async -> [SourceItem] {
        var result: [SourceItem] = []
        for app in apps {
            guard !Task.isCancelled else { break }
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
                  let bar else { continue }
            let barElement = unsafeDowncast(bar, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(barElement, 0.05)
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement] else { continue }
            for child in elements {
                AXUIElementSetMessagingTimeout(child, 0.05)
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &positionValue) == .success,
                      AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue) == .success,
                      let positionValue, let sizeValue,
                      CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
                var position = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
                      AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { continue }
                result.append(SourceItem(pid: app.pid, name: app.name, frame: CGRect(origin: position, size: size)))
            }
        }
        return result
    }
}

enum MenuItems {
    private static var orderKeyCache: [CGWindowID: (bundle: String, title: String, key: String)] = [:]
    // The window capture API remains available at runtime on macOS 26. It can
    // capture offscreen status windows, which ScreenCaptureKit cannot yet do.
    private typealias Capture = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    private static let capture: Capture? = {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(address, to: Capture.self)
    }()

    static func windowInfo(onScreenOnly: Bool = false) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func frame(of window: NSWindow?, title: String, preferVisible: Bool = false) -> CGRect? {
        let infos = windowInfo()
        // Tahoe hosts status windows inside Control Center. Its hosted window
        // keeps the autosave title, while the app's proxy has another number.
        guard let info = infos.first(where: { ($0[kCGWindowName as String] as? String) == title }) ?? infos.first(where: { ($0[kCGWindowNumber as String] as? Int) == window?.windowNumber }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        // The titled control can belong to a retracted menu bar on another
        // display. Tahoe labels its visible mirror with our bundle identifier.
        if preferVisible && (info[kCGWindowIsOnscreen as String] as? Bool) != true,
           let bundleID = Bundle.main.bundleIdentifier {
            for mirror in infos where (mirror[kCGWindowName as String] as? String) == bundleID &&
                (mirror[kCGWindowIsOnscreen as String] as? Bool) == true &&
                (mirror[kCGWindowLayer as String] as? Int) == Int(kCGStatusWindowLevel) {
                if let bounds = mirror[kCGWindowBounds as String] as? NSDictionary,
                   let candidate = CGRect(dictionaryRepresentation: bounds),
                   abs(candidate.width - frame.width) < 1, abs(candidate.height - frame.height) < 1 {
                    return candidate
                }
            }
        }
        return frame
    }

    static func read(divider: CGRect, captureImages: Bool, sources: [SourceItem], knownItems: [MenuItem] = [], requireSource: Bool = true) -> [MenuItem] {
        let infos = windowInfo()
        let liveIDs = Set(infos.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        orderKeyCache = orderKeyCache.filter { liveIDs.contains($0.key) }
        var orderKeys: [CGWindowID: String] = [:]
        // Count same-app extras across the native row, including visible ones,
        // so bundling another extra does not renumber existing saved entries.
        let rowWindows = infos.compactMap { info -> (CGWindowID, CGRect, String)? in
            guard (info[kCGWindowLayer as String] as? Int) == Int(kCGStatusWindowLevel),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  abs(frame.minY - divider.minY) < 2 else { return nil }
            return (id, frame, info[kCGWindowName as String] as? String ?? "")
        }.sorted { $0.1.minX < $1.1.minX }
        let rowIDs = Set(rowWindows.filter { id, frame, _ in
            knownItems.contains { $0.id == id } || sources.contains {
                abs($0.frame.midX - frame.midX) < 2 && abs($0.frame.midY - frame.midY) < 2
            }
        }.map { $0.0 })
        // Only AX-backed source windows reserve identities. Other displays'
        // mirrors, including aligned rows, may share the same logical key.
        var usedKeys = Set(orderKeyCache.filter { rowIDs.contains($0.key) }.values.map(\.key))
        for (id, frame, title) in rowWindows {
            let known = knownItems.first { $0.id == id }
            let sourcePID = known?.sourcePID ?? sources.first {
                abs($0.frame.midX - frame.midX) < 2 && abs($0.frame.midY - frame.midY) < 2
            }?.pid
            guard let sourcePID,
                  let bundle = NSRunningApplication(processIdentifier: sourcePID)?.bundleIdentifier else { continue }
            if let cached = orderKeyCache[id], cached.bundle == bundle, cached.title == title {
                orderKeys[id] = cached.key
                continue
            }
            var occurrence = 0
            var key = ShelfOrder.identity(bundle: bundle, title: title, occurrence: occurrence)
            while usedKeys.contains(key) {
                occurrence += 1
                key = ShelfOrder.identity(bundle: bundle, title: title, occurrence: occurrence)
            }
            orderKeyCache[id] = (bundle, title, key)
            usedKeys.insert(key)
            orderKeys[id] = key
        }
        return infos.compactMap { info -> MenuItem? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == Int(kCGStatusWindowLevel),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  TrayGeometry.belongsInTray(item: frame, divider: divider)
            else { return nil }
            // Hosted window IDs survive a divider resize, while Accessibility
            // frames can lag behind. Retain the already verified source during
            // that transition so the first collapsed frame keeps its items.
            let known = knownItems.first { $0.id == id }
            // During reordering, stale AX coordinates can now belong to a
            // different icon. Prefer the verified window identity until rescan.
            let source = known.map { SourceItem(pid: $0.sourcePID, name: $0.name, frame: frame) }
                ?? sources.first { abs($0.frame.midX - frame.midX) < 2 && abs($0.frame.midY - frame.midY) < 2 }
            let sourcePID = source?.pid ?? pid
            guard sourcePID != ProcessInfo.processInfo.processIdentifier else { return nil }
            let app = NSRunningApplication(processIdentifier: sourcePID)
            // Other displays have duplicate hosted status windows. Only the
            // real extras exposed by the source apps are interactive here.
            if requireSource && app?.bundleIdentifier == "com.apple.controlcenter" && source == nil { return nil }
            let name = app?.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? "Menu item"
            let title = info[kCGWindowName as String] as? String ?? ""
            guard title != "Tray.Divider", title != "Tray.Trigger" else { return nil }
            let label = source?.name ?? (app?.bundleIdentifier == "com.apple.controlcenter" && !title.isEmpty ? title : name)
            var image: NSImage?
            if captureImages {
                var windowPointer = UnsafeRawPointer(bitPattern: UInt(id))
                if let array = CFArrayCreate(kCFAllocatorDefault, &windowPointer, 1, nil),
                   let cgImage = capture?(.null, array, CGWindowImageOption.boundsIgnoreFraming.rawValue)?.takeRetainedValue() {
                    image = NSImage(cgImage: cgImage, size: frame.size)
                }
            }
            return MenuItem(id: id, pid: pid, sourcePID: sourcePID, name: label, frame: frame, image: image ?? app?.icon, isLiveImage: image != nil, orderKey: orderKeys[id] ?? "session:\(id)")
        }.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func requestScreenAccess() {
        SCShareableContent.getWithCompletionHandler { _, _ in }
        openPrivacy("Privacy_ScreenCapture")
    }

    static func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
