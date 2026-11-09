import AppKit
@preconcurrency import ApplicationServices

nonisolated struct MenuPathComponent: Sendable {
    let index: Int
    let role: String
    let title: String
    let identifier: String?
}

nonisolated enum BundledMenuRead: Sendable {
    case menu([BundledMenuEntry])
    case noMenu
    case unavailable
}

nonisolated struct PopupActivation: Sendable {
    let performed: Bool
    let windowID: UInt32?
}

nonisolated struct BundledMenuEntry: Sendable {
    let title: String
    let enabled: Bool
    let checked: Bool
    let shortcut: String
    let modifiers: Int
    let path: [MenuPathComponent]
    let children: [BundledMenuEntry]
}

/// Reads the app's exposed menu without opening it or moving its status item.
/// Commands resolve the original Accessibility action again when selected.
enum BundledMenuAccess {
    nonisolated private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        switch error {
        case .success: return result
        case .attributeUnsupported, .noValue: return nil
        default: throw ReadError.incomplete
        }
    }

    nonisolated private static func children(_ element: AXUIElement) throws -> [AXUIElement] {
        guard let result = try attribute(element, kAXChildrenAttribute) else { return [] }
        guard let items = result as? [AXUIElement] else { throw ReadError.incomplete }
        return items
    }

    nonisolated private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    nonisolated private static func statusItem(pid: pid_t, expected: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar = value(app, kAXExtrasMenuBarAttribute) else { return nil }
        let element = unsafeDowncast(bar, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.1)
        return ((try? children(element)) ?? []).first {
            AXUIElementSetMessagingTimeout($0, 0.1)
            guard let actual = frame($0) else { return false }
            // The AX button can be smaller than its hosted status window.
            return abs(actual.midX - expected.midX) < 3 && abs(actual.midY - expected.midY) < 3
        }
    }

    nonisolated private enum ReadError: Error { case incomplete }

    @concurrent nonisolated static func menu(pid: pid_t, frame: CGRect) async -> BundledMenuRead {
        guard let item = statusItem(pid: pid, expected: frame), !Task.isCancelled else { return .unavailable }
        do {
            guard try children(item).contains(where: { try attribute($0, kAXRoleAttribute) as? String == kAXMenuRole }) else {
                return .noMenu
            }
        } catch { return .unavailable }
        var remaining = 200
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        func read(_ parent: AXUIElement, path: [MenuPathComponent], depth: Int) throws -> [BundledMenuEntry] {
            guard depth < 8, !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.incomplete }
            var result: [BundledMenuEntry] = []
            for (index, child) in try children(parent).enumerated() {
                guard remaining > 0, !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.incomplete }
                remaining -= 1
                AXUIElementSetMessagingTimeout(child, 0.05)
                guard let role = try attribute(child, kAXRoleAttribute) as? String else { throw ReadError.incomplete }
                let title = try attribute(child, kAXTitleAttribute) as? String ?? ""
                let childPath = path + [MenuPathComponent(index: index, role: role, title: title,
                    identifier: try attribute(child, kAXIdentifierAttribute) as? String)]
                if role == kAXMenuRole {
                    result += try read(child, path: childPath, depth: depth + 1)
                } else if role == kAXMenuItemRole {
                    let nested = try children(child).isEmpty ? [] : read(child, path: childPath, depth: depth + 1)
                    result.append(BundledMenuEntry(title: title,
                        enabled: try attribute(child, kAXEnabledAttribute) as? Bool ?? false,
                        checked: !(try attribute(child, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty,
                        shortcut: try attribute(child, kAXMenuItemCmdCharAttribute) as? String ?? "",
                        modifiers: try attribute(child, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0,
                        path: childPath, children: nested))
                }
            }
            return result
        }
        guard let result = try? read(item, path: [], depth: 0), !result.isEmpty else { return .unavailable }
        return .menu(result)
    }

    @concurrent nonisolated static func perform(pid: pid_t, frame: CGRect, entry: BundledMenuEntry) async -> Bool {
        guard var element = statusItem(pid: pid, expected: frame) else { return false }
        for component in entry.path {
            guard let items = try? children(element) else { return false }
            guard items.indices.contains(component.index), !Task.isCancelled else { return false }
            element = items[component.index]
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard value(element, kAXRoleAttribute) as? String == component.role,
                  (value(element, kAXTitleAttribute) as? String ?? "") == component.title else { return false }
            if let identifier = component.identifier,
               value(element, kAXIdentifierAttribute) as? String != identifier { return false }
        }
        // A dynamic menu may have changed since it was displayed. Never send
        // a command to a different item that happens to occupy the same index.
        guard value(element, kAXTitleAttribute) as? String == entry.title,
              value(element, kAXEnabledAttribute) as? Bool == true, !Task.isCancelled else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @concurrent nonisolated static func press(pid: pid_t, frame expected: CGRect,
                                             anchor: CGRect, display: CGRect) async -> PopupActivation {
        func windows() -> [[String: Any]] {
            (CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []).filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
            }
        }
        let before = Set(windows().compactMap { $0[kCGWindowNumber as String] as? UInt32 })
        guard let item = statusItem(pid: pid, expected: expected), !Task.isCancelled,
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            return PopupActivation(performed: false, windowID: nil)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.75
        for _ in 0..<16 {
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return PopupActivation(performed: true, windowID: nil) }
            for window in windows() {
                guard let id = window[kCGWindowNumber as String] as? UInt32, !before.contains(id),
                      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds),
                      rect.width >= 40, rect.height >= 30,
                      rect.width < display.width * 0.7, rect.height < display.height * 0.8 else { continue }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.05)
                var candidates = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
                // AppKit exposes status-item popovers as children of the
                // extras menu bar, not necessarily in the app's window list.
                if let extras = value(app, kAXExtrasMenuBarAttribute) {
                    let bar = unsafeDowncast(extras, to: AXUIElement.self)
                    AXUIElementSetMessagingTimeout(bar, 0.05)
                    candidates += (try? children(bar)) ?? []
                }
                for element in candidates {
                    guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else {
                        return PopupActivation(performed: true, windowID: nil)
                    }
                    AXUIElementSetMessagingTimeout(element, 0.05)
                    let isPopover = value(element, kAXRoleAttribute) as? String == "AXPopover" ||
                        value(element, kAXSubroleAttribute) as? String == "AXPopover" ||
                        ((try? children(element)) ?? []).contains { value($0, kAXRoleAttribute) as? String == "AXPopover" }
                    guard isPopover, let actual = frame(element),
                          abs(actual.midX - rect.midX) < 14, abs(actual.midY - rect.midY) < 14,
                          abs(actual.width - rect.width) < 24, abs(actual.height - rect.height) < 24,
                          value(element, kAXSubroleAttribute) as? String != kAXStandardWindowSubrole else { continue }
                    var movable: DarwinBoolean = false
                    guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success,
                          movable.boolValue else { continue }
                    var origin = CGPoint(
                        x: max(display.minX + 8, min(display.maxX - actual.width - 8, anchor.midX - actual.width / 2)),
                        y: max(display.minY + 8, min(display.maxY - actual.height - 8, anchor.maxY + 2)))
                    guard !Task.isCancelled, let position = AXValueCreate(.cgPoint, &origin) else {
                        return PopupActivation(performed: true, windowID: nil)
                    }
                    if AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success {
                        return PopupActivation(performed: true, windowID: id)
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
        // Apps own their custom windows. Ordinary app windows and popovers
        // that refuse positioning retain the source app's normal behavior.
        return PopupActivation(performed: true, windowID: nil)
    }
}

final class BundledMenuPresenter: NSObject {
    private final class Command: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func invoke() { handler() }
    }
    private var commands: [Command] = []
    private var menu: NSMenu?

    func show(_ entries: [BundledMenuEntry], at anchor: CGRect, in view: NSView, select: @escaping (BundledMenuEntry) -> Void) -> Bool {
        commands = []
        func makeMenu(_ entries: [BundledMenuEntry]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for entry in entries {
                if entry.title.isEmpty && entry.children.isEmpty {
                    menu.addItem(.separator())
                    continue
                }
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: entry.shortcut.lowercased())
                item.isEnabled = entry.enabled
                item.state = entry.checked ? .on : .off
                var flags: NSEvent.ModifierFlags = entry.modifiers & 8 == 0 ? [.command] : []
                if entry.modifiers & 1 != 0 { flags.insert(.shift) }
                if entry.modifiers & 2 != 0 { flags.insert(.option) }
                if entry.modifiers & 4 != 0 { flags.insert(.control) }
                item.keyEquivalentModifierMask = flags
                if !entry.children.isEmpty {
                    item.submenu = makeMenu(entry.children)
                } else {
                    let command = Command { select(entry) }
                    commands.append(command)
                    item.target = command
                    item.action = #selector(Command.invoke)
                }
                menu.addItem(item)
            }
            return menu
        }
        let menu = makeMenu(entries)
        self.menu = menu
        guard let window = view.window else { self.menu = nil; return false }
        let point = view.convert(window.convertPoint(fromScreen: CGPoint(x: anchor.minX, y: anchor.minY)), from: nil)
        NSApp.activate(ignoringOtherApps: true)
        let selected = menu.popUp(positioning: nil, at: point, in: view)
        self.menu = nil
        // AppKit can deliver the selected item's action after tracking ends.
        // Keep its targets alive until the next menu replaces them.
        return selected
    }

    func cancel() { menu?.cancelTracking() }
}
