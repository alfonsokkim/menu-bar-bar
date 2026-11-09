import AppKit
@preconcurrency import ApplicationServices
import ServiceManagement
import SwiftUI
import QuartzCore
import TrayCore
import os

@main
struct TrayApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = TrayController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class TrayController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var isArranging = false
    @Published var screenAccess = false
    @Published var accessibilityAccess = false
    @Published var message = ""
    @Published var menuBarSurface: NSImage?
    @Published var menuBarSurfaceFrame: CGRect = .zero
    @Published var rowHeight: CGFloat = NSStatusBar.system.thickness
    @Published var shelfPresented = false
    @Published var shelfOriginX: CGFloat = 0
    @Published var shelfJoinHeight: CGFloat = 1
    private(set) var shelfPresentationRevision = 0
    private(set) var animatesShelf = true
    @Published var chevronPhase: CGFloat = 0
    private(set) var chevronMenuHeight: CGFloat = 30
    private(set) var chevronForeground: Color = .white
    private(set) var chevronOriginX: CGFloat = 0
    @Published var isRefreshing = false
    private var trigger: NSStatusItem!
    private var divider: NSStatusItem!
    private var panel: ShelfPanel?
    private var shelfFrameTarget: CGRect?
    private var chevronPanel: ChevronPanel?
    private var chevronTask: Task<Void, Never>?
    private let chevronImage = ChevronArtwork.image()
    private let hiddenChevronImage = ChevronArtwork.image(hidden: true)
    private var settings: NSWindow?
    private var timer: Timer?
    private var surfaceTimer: Timer?
    private var surfaceTask: Task<Void, Never>?
    private var surfaceSample: (background: MenuBarBackdrop.Background, frame: CGRect, scale: CGFloat)?
    var menuBarWindowID: CGWindowID? { surfaceSample?.background.windowID }
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    var itemFrames: [UInt32: CGRect] = [:]
    private var isPresentingBundledMenu = false
    private let bundledMenuPresenter = BundledMenuPresenter()
    private var activePopupID: UInt32?
    private var activationTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    @Published var movingItemID: UInt32?
    @Published var shelfDraggedItemID: UInt32?
    @Published var shelfDropIndicatorX: CGFloat?
    @Published var availableToBundle: [AvailableStatusItem] = []
    private let dragMonitor = StatusDragMonitor()
    private var savedShelfOrder = UserDefaults.standard.stringArray(forKey: "shelfItemOrder") ?? []
    private var nativeDrag: (item: StatusWindow, start: CGPoint, target: CGRect, moved: Bool, keyCount: UInt32)?
    private var shelfDropContext: (bar: CGRect, trigger: StatusWindow)?

    private var notifications: [NSObjectProtocol] = []
    private var scanTask: Task<Void, Never>?
    private var sources: [SourceItem] = []
    private var sourceTransitionItems: [MenuItem] = []
    private var triggerFrame = CGRect.zero
    private let backdrop = MenuBarBackdrop()

    func applicationDidFinishLaunching(_ notification: Notification) {
        trigger = NSStatusBar.system.statusItem(withLength: 28)
        trigger.autosaveName = "Tray.Trigger"
        trigger.button?.image = chevronImage
        trigger.button?.toolTip = "Menu Bar Bar. Click to open, right-click for options."
        trigger.button?.target = self
        trigger.button?.action = #selector(toggle)
        trigger.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        divider = NSStatusBar.system.statusItem(withLength: 18)
        divider.autosaveName = "Tray.Divider"
        divider.button?.toolTip = "Command-drag the icons you want in Tray to the LEFT of this divider."
        divider.button?.target = self
        divider.button?.action = #selector(showSettings)

        isArranging = !UserDefaults.standard.bool(forKey: "hasFinishedSetup")
        updateDivider()
        dragMonitor.handle = { [weak self] phase, point, command in
            self?.handleNativeDrag(phase, at: point, command: command)
        }
        dragMonitor.start()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown && event.modifierFlags.contains(.command) { return }
                guard let self, self.moveTask == nil, self.shelfDraggedItemID == nil, !self.isPresentingBundledMenu, !self.triggerFrame.contains(NSEvent.mouseLocation),
                      !self.pointerIsInsidePopup() else { return }
                self.hideShelf()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if let token = event.cgEvent?.getIntegerValueField(.eventSourceUserData), StatusItemMover.isMoveEvent(token) { return event }
                if self?.moveTask != nil { return event }
            }
            if self?.shelfDraggedItemID != nil {
                if event.type == .keyDown && event.keyCode == 53 { self?.cancelDrag() }
                return event
            }
            if self?.isPresentingBundledMenu == true { return event }
            if event.type == .keyDown && event.keyCode == 53 &&
                (self?.panel?.isVisible == true || self?.chevronTask != nil) {
                self?.hideShelf(animated: false)
                return nil
            }
            if event.type != .keyDown && event.window !== self?.panel && event.window !== self?.trigger.button?.window {
                self?.hideShelf()
            }
            return event
        }
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideShelf(animated: false); self?.refresh() }
        })
        notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideShelf(animated: false) }
        })
        if isArranging { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
        divider.length = 18
        activationTask?.cancel()
        commandTask?.cancel()
        moveTask?.cancel()
        chevronTask?.cancel()
        timer?.invalidate()
        surfaceTimer?.invalidate()
        surfaceTask?.cancel()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    private func updateDivider() {
        let length: CGFloat = isArranging ? 18 : 10000
        if divider.length != length {
            sourceTransitionItems = items
            scanTask?.cancel()
            scanTask = nil
        }
        divider.length = length
        divider.button?.image = isArranging ? NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Tray divider") : nil
        trigger.button?.image = shelfPresented ? hiddenChevronImage : chevronImage
    }

    func refresh() {
        screenAccess = CGPreflightScreenCaptureAccess()
        accessibilityAccess = AXIsProcessTrusted()
        if accessibilityAccess && scanTask == nil && movingItemID == nil && shelfDraggedItemID == nil {
            isRefreshing = true
            let apps = NSWorkspace.shared.runningApplications.filter { $0.isFinishedLaunching && !$0.isTerminated && $0.activationPolicy != .prohibited }
                .map { SourceApp(pid: $0.processIdentifier, name: $0.localizedName ?? "Menu item") }
            scanTask = Task { [weak self] in
                if self?.sourceTransitionItems.isEmpty == false {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                }
                let sources = await MenuAccessibility.scan(apps)
                guard !Task.isCancelled, let self else { return }
                self.sources = sources
                self.sourceTransitionItems = []
                self.scanTask = nil
                self.isRefreshing = false
                self.updateItems()
            }
        }
        updateItems()
    }

    private func updateItems() {
        guard shelfDraggedItemID == nil, movingItemID == nil else { return }
        guard let frame = MenuItems.frame(of: divider.button?.window, title: "Tray.Divider") else { return }
        availableToBundle = StatusWindow.all().compactMap { window in
            guard window.frame.width < 500, window.frame.minX >= frame.maxX - 1,
                  abs(window.frame.midY - frame.midY) < 3,
                  let source = sources.first(where: { abs($0.frame.midX - window.frame.midX) < 3 && abs($0.frame.midY - window.frame.midY) < 3 }),
                  source.pid != ProcessInfo.processInfo.processIdentifier,
                  !["Clock", "BentoBox-0", "AudioVideoModule"].contains(window.title) else { return nil }
            return AvailableStatusItem(window: window, name: source.name)
        }
        let latest = MenuItems.read(divider: frame, captureImages: screenAccess && panel?.isVisible == true, sources: sources, knownItems: sourceTransitionItems)
        let previousIDs = items.map(\.id)
        if !latest.isEmpty || scanTask == nil {
            items = ShelfOrder.indices(for: latest.map(\.orderKey), saved: savedShelfOrder).map { latest[$0] }
        }
        if let panel, panel.isVisible {
            layoutShelf(panel, animateResize: previousIDs != items.map(\.id))
        }
    }

    private var isGeneratedMoveClick: Bool {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseUp,
              let mouseEvent = event.cgEvent else { return false }
        return StatusItemMover.isMoveEvent(mouseEvent.getIntegerValueField(.eventSourceUserData))
    }

    @objc private func toggle() {
        guard moveTask == nil, !isGeneratedMoveClick else { return }
        if NSApp.currentEvent?.type == .rightMouseUp || NSEvent.modifierFlags.contains(.option) {
            showMenu()
            return
        }
        if isArranging && !items.isEmpty {
            finishSetup()
            return
        }
        if shelfPresented { hideShelf(); return }
        let shelf: ShelfPanel
        if let panel {
            shelf = panel
        } else {
            shelf = ShelfPanel()
            panel = shelf
        }
        shelfPresentationRevision += 1
        animatesShelf = NSApp.currentEvent?.type != .keyDown && NSApp.currentEvent?.type != .keyUp
        shelfPresented = true
        backdrop.invalidate()
        refresh()
        layoutShelf(shelf, forceSurfaceRefresh: true)
        let needsContent = !shelf.isVisible || !(shelf.contentView is NSHostingView<ShelfView>)
        // Mount only after opening state is established. An initial closed
        // SwiftUI callback must never dismiss the host being opened.
        if needsContent { shelf.contentView = ShelfHostingView(controller: self) }
        shelf.makeKeyAndOrderFront(nil)
        startSurfaceRefresh()
        updateItems()
        animateChevron(opening: true, animated: animatesShelf)
    }

    private func layoutShelf(_ shelf: ShelfPanel, forceSurfaceRefresh: Bool = false, animateResize: Bool = false) {
        guard let window = trigger.button?.window,
              var screen = window.screen ?? NSScreen.main else { return }
        var anchor = window.frame
        // Synthetic native movement can briefly reveal another display's menu
        // bar. Keep an open shelf on its original display through that handoff.
        let retainedAnchor = shelf.isVisible && shelfPresented && !triggerFrame.isEmpty ? triggerFrame : nil
        if let retainedAnchor {
            anchor = retainedAnchor
            screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? screen
        }
        if let hostedFrame = MenuItems.frame(of: window, title: "Tray.Trigger", preferVisible: true), let main = NSScreen.screens.first {
            let candidate = CGRect(x: hostedFrame.minX, y: main.frame.maxY - hostedFrame.maxY, width: hostedFrame.width, height: hostedFrame.height)
            if retainedAnchor == nil || screen.frame.contains(CGPoint(x: candidate.midX, y: candidate.midY)) {
                anchor = candidate
                screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? screen
            }
        }
        let background = backdrop.background(for: screen)
        rowHeight = background?.barFrame.height ?? max(NSStatusBar.system.thickness, anchor.height)
        let width: CGFloat = items.isEmpty ? rowHeight * 8 : items.reduce(0) {
            $0 + ShelfSurface.cellWidth(itemWidth: $1.frame.width)
        }
        let menuBarBottom = background.flatMap { value in NSScreen.screens.first.map { $0.frame.maxY - value.barFrame.maxY } } ?? anchor.minY
        triggerFrame = anchor
        let frame = ShelfSurface.frame(anchor: anchor, screen: screen.frame, menuBarBottom: menuBarBottom,
                                       bodyWidth: width, height: rowHeight, scale: screen.backingScaleFactor)
        shelfJoinHeight = 1 / max(1, screen.backingScaleFactor)
        let panelFrame = ShelfSurface.panelFrame(bodyFrame: frame, scale: screen.backingScaleFactor)
        let targetChanged = shelfFrameTarget != panelFrame
        let shouldAnimate = animateResize && shelfPresented && shelf.isVisible &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && chevronTask == nil
        // Cover the whole resize path. The view crops the material in screen
        // coordinates instead of stretching the final sample during the tween.
        let sampleFrame: CGRect
        if targetChanged && shouldAnimate {
            let left = min(shelf.frame.minX, frame.minX)
            let right = max(shelf.frame.maxX, frame.maxX)
            sampleFrame = CGRect(x: left, y: frame.minY, width: right - left, height: frame.height)
        } else if !targetChanged, surfaceSample?.background == background, let sample = surfaceSample {
            sampleFrame = sample.frame
        } else {
            sampleFrame = frame
        }
        if targetChanged || !shelf.isVisible {
            shelfFrameTarget = panelFrame
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                    shelf.animator().setFrame(panelFrame, display: true)
                }
            } else {
                shelf.setFrame(panelFrame, display: true)
            }
        }
        shelfOriginX = anchor.midX - frame.minX
        let sampleChanged = surfaceSample?.background != background ||
            surfaceSample?.frame != sampleFrame || surfaceSample?.scale != screen.backingScaleFactor
        if sampleChanged || !shelfPresented || forceSurfaceRefresh {
            surfaceTask?.cancel()
            surfaceTask = nil
            surfaceSample = background.map { ($0, sampleFrame, screen.backingScaleFactor) }
            refreshSurface()
        } else {
            refreshSurfaceInBackground()
        }
    }

    private func refreshSurface() {
        // The falling strokes briefly cross the sampled row. Keep the clean
        // background until they have finished so they cannot leave a stripe.
        guard chevronTask == nil else { return }
        menuBarSurfaceFrame = surfaceSample?.frame ?? .zero
        menuBarSurface = screenAccess ? surfaceSample.flatMap {
            backdrop.image(for: $0.background, shelfFrame: $0.frame, scale: $0.scale)
        } : nil
    }

    private func refreshSurfaceInBackground() {
        guard screenAccess else {
            surfaceTask?.cancel()
            surfaceTask = nil
            menuBarSurface = nil
            return
        }
        guard surfaceTask == nil, chevronTask == nil, let sample = surfaceSample else { return }
        surfaceTask = Task { [weak self] in
            let image = await MenuBarBackdrop.refreshedImage(for: sample.background,
                                                           shelfFrame: sample.frame, scale: sample.scale)
            guard !Task.isCancelled, let self else { return }
            self.surfaceTask = nil
            guard self.screenAccess, self.shelfPresented, self.chevronTask == nil,
                  let image, image.width > 0, image.height > 0 else { return }
            self.menuBarSurfaceFrame = sample.frame
            self.menuBarSurface = NSImage(cgImage: image,
                                         size: CGSize(width: sample.frame.width, height: CGFloat(image.height) / max(1, sample.scale)))
        }
    }

    private func startSurfaceRefresh() {
        surfaceTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shelfPresented else { return }
                self.refreshSurfaceInBackground()
            }
        }
        timer.tolerance = 0.02
        // Native menus track in a separate run-loop mode. Keep matching their
        // background without repeating the slower Accessibility icon scan.
        RunLoop.main.add(timer, forMode: .common)
        surfaceTimer = timer
    }

    func hideShelf(animated: Bool = true) {
        cancelDrag()
        moveTask?.cancel()
        surfaceTimer?.invalidate()
        surfaceTimer = nil
        surfaceTask?.cancel()
        surfaceTask = nil
        activationTask?.cancel()
        bundledMenuPresenter.cancel()
        activePopupID = nil
        guard panel?.isVisible == true || shelfPresented || chevronTask != nil || chevronPanel?.isVisible == true else { return }
        guard shelfPresented || !animated else { return }
        shelfPresentationRevision += 1
        animatesShelf = animated
        shelfPresented = false
        animateChevron(opening: false, animated: animated)
        if !animated {
            panel?.orderOut(nil)
            panel?.contentView = nil
        }
    }

    func finishShelfDismissal(revision: Int) {
        guard revision == shelfPresentationRevision, !shelfPresented else { return }
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func animateChevron(opening: Bool, animated: Bool) {
        surfaceTask?.cancel()
        surfaceTask = nil
        chevronTask?.cancel()
        chevronTask = nil
        let target: CGFloat = opening ? 1 : 0
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              triggerFrame.height > 0 else {
            chevronPhase = target
            chevronPanel?.orderOut(nil)
            trigger.button?.image = opening ? hiddenChevronImage : chevronImage
            return
        }
        let overlay = chevronPanel ?? ChevronPanel()
        chevronPanel = overlay
        chevronMenuHeight = triggerFrame.height
        chevronForeground = ChevronArtwork.foreground(over: menuBarSurface)
        if !(overlay.contentView is NSHostingView<ChevronSplashView>) {
            overlay.contentView = NSHostingView(rootView: ChevronSplashView(controller: self))
        }
        let shelfFrame = panel?.frame ?? CGRect(x: triggerFrame.midX - 52, y: 0, width: 104, height: rowHeight)
        chevronOriginX = triggerFrame.midX - shelfFrame.minX
        overlay.setFrame(CGRect(x: shelfFrame.minX, y: triggerFrame.minY - rowHeight,
                                width: shelfFrame.width, height: triggerFrame.height + rowHeight), display: true)
        trigger.button?.image = hiddenChevronImage
        overlay.orderFrontRegardless()
        // The strokes are already invisible past 0.6. Start their return there
        // so closing does not wait through an invisible part of the trajectory.
        let start = opening ? chevronPhase : min(0.6, chevronPhase)
        chevronPhase = start
        let duration = max(0.08, 0.22 * Double(abs(target - start)))
        let began = ProcessInfo.processInfo.systemUptime
        chevronTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
                // Geometry supplies a fall from rest under gravity. Reversing
                // the same trajectory reforms the two strokes as they rise.
                self.chevronPhase = start + (target - start) * elapsed
                if elapsed >= 1 || (opening && self.chevronPhase >= 0.6) {
                    self.chevronPhase = target
                    self.chevronPanel?.orderOut(nil)
                    self.trigger.button?.image = opening ? self.hiddenChevronImage : self.chevronImage
                    self.chevronTask = nil
                    if self.shelfPresented { self.refreshSurfaceInBackground() }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    func arrange() {
        activationTask?.cancel()
        isArranging = true
        updateDivider()
        hideShelf(animated: false)
        showSettings()
    }

    func finishSetup() {
        let wasArranging = isArranging
        UserDefaults.standard.set(true, forKey: "hasFinishedSetup")
        isArranging = false
        updateDivider()
        settings?.orderOut(nil)
        message = ""
        if wasArranging {
            hideShelf(animated: false)
            toggle()
        }
    }

    func previewShelf() { toggle() }

    private func pointerIsInsidePopup() -> Bool {
        guard let id = activePopupID, let primary = NSScreen.screens.first,
              let info = MenuItems.windowInfo(onScreenOnly: true).first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
        let point = NSEvent.mouseLocation
        return frame.contains(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
    }

    private func quartzPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }

    private func visibleTrigger() -> StatusWindow? {
        guard let frame = MenuItems.frame(of: trigger.button?.window, title: "Tray.Trigger", preferVisible: true) else { return nil }
        return StatusWindow.all().first { $0.frame == frame }
    }

    private func cancelDrag() {
        nativeDrag = nil
        shelfDropContext = nil
        shelfDraggedItemID = nil
        shelfDropIndicatorX = nil
        trigger.button?.highlight(false)
    }

    private func handleNativeDrag(_ phase: StatusDragMonitor.Phase, at point: CGPoint, command: Bool) {
        if phase == .cancelled { cancelDrag(); moveTask?.cancel(); return }
        guard moveTask == nil, shelfDraggedItemID == nil else { return }
        let point = quartzPoint(point)
        // A keypress during the native drag cancels our drop handling. Reading
        // the aggregate counter catches Escape without observing typed keys.
        if let drag = nativeDrag, phase != .began,
           drag.keyCount != CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown) {
            cancelDrag()
            return
        }
        switch phase {
        case .began:
            nativeDrag = nil
            guard command, let trigger = visibleTrigger(),
                  let item = StatusWindow.all().first(where: { $0.frame.contains(point) && $0.frame.height <= 64 && $0.frame.width < 500 }),
                  item.id != trigger.id, item.title != "Tray.Divider", item.title != Bundle.main.bundleIdentifier,
                  abs(item.frame.midY - trigger.frame.midY) < 3,
                  !["Clock", "BentoBox-0", "AudioVideoModule"].contains(item.title) else { return }
            nativeDrag = (item, point, trigger.frame, false, CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown))
        case .moved:
            guard var drag = nativeDrag else { return }
            drag.moved = drag.moved || StatusDragGeometry.isDrag(from: drag.start, to: point)
            if let trigger = visibleTrigger() { drag.target = trigger.frame }
            nativeDrag = drag
            self.trigger.button?.highlight(drag.moved && drag.target.contains(point))
        case .ended:
            guard let drag = nativeDrag else { return }
            nativeDrag = nil
            self.trigger.button?.highlight(false)
            guard drag.moved, drag.target.insetBy(dx: -2, dy: 0).contains(point) else { return }
            self.trigger.button?.highlight(true)
            // Let the user's native mouse-up finish before starting our move.
            moveTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch {
                    self?.moveTask = nil
                    self?.trigger.button?.highlight(false)
                    return
                }
                guard let self else { return }
                self.moveTask = nil
                self.bundleStatusItem(drag.item)
                if self.moveTask == nil { self.trigger.button?.highlight(false) }
            }
        case .cancelled: break
        }
    }

    func beginShelfDrag(_ id: UInt32) -> Bool {
        guard accessibilityAccess, shelfPresented, movingItemID == nil, shelfDraggedItemID == nil,
              items.contains(where: { $0.id == id }) else { return false }
        activationTask?.cancel()
        bundledMenuPresenter.cancel()
        nativeDrag = nil
        shelfDropContext = currentShelfDropContext()
        shelfDraggedItemID = id
        return true
    }

    private func shelfReorderSlot(_ id: UInt32, at point: CGPoint) -> ShelfReorderSlot? {
        guard shelfPresented, let panel, panel.isVisible else { return nil }
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        let viewport = CGRect(x: ShelfSurface.flare, y: shelfJoinHeight,
                              width: max(0, panel.frame.width - 2 * ShelfSurface.flare), height: rowHeight)
        let cells = items.compactMap { item in
            itemFrames[item.id].map { ShelfDragCell(id: item.id, frame: $0) }
        }
        return StatusDragGeometry.reorderSlot(for: id, at: local, viewport: viewport, cells: cells)
    }

    @discardableResult
    func updateShelfDrag(at point: CGPoint, imageFrame: CGRect? = nil) -> Bool {
        guard let id = shelfDraggedItemID else { shelfDropIndicatorX = nil; return false }
        if menuBarDropTarget(at: point, imageFrame: imageFrame) != nil {
            shelfDropIndicatorX = nil
            return false
        }
        let slot = shelfReorderSlot(id, at: point)
        shelfDropIndicatorX = slot?.indicatorX
        return slot != nil
    }

    func finishShelfDrag(_ id: UInt32, at point: CGPoint, imageFrame: CGRect?, mouseReleased: Bool) {
        guard shelfDraggedItemID == id else { return }
        defer { shelfDropContext = nil }
        shelfDraggedItemID = nil
        shelfDropIndicatorX = nil
        guard mouseReleased, shelfPresented, items.contains(where: { $0.id == id }) else { return }
        shelfDropContext = currentShelfDropContext()
        let dropTarget = menuBarDropTarget(at: point, imageFrame: imageFrame)
        shelfDropContext = nil
        if dropTarget == nil, let slot = shelfReorderSlot(id, at: point) {
            reorderShelfItem(id, beside: slot.targetID, before: slot.onLeft)
            return
        }
        guard let source = StatusWindow.current(id),
              items.contains(where: { $0.id == id && $0.pid == source.pid }) else { return }
        guard let (drop, bar, trigger) = dropTarget else { return }
        let target: StatusWindow
        let side: StatusItemMover.Side
        if drop.x < trigger.frame.minX {
            target = trigger
            side = .left
        } else {
            let candidates = StatusWindow.all().filter {
                $0.id != id && $0.title != "Tray.Divider" && $0.frame.width < 500 &&
                abs($0.frame.midY - bar.midY) < 3 && $0.frame.minX >= trigger.frame.minX &&
                $0.frame.maxX <= bar.maxX
            }
            guard let nearest = candidates.min(by: { abs($0.frame.midX - drop.x) < abs($1.frame.midX - drop.x) }) else { return }
            target = nearest
            side = drop.x < nearest.frame.midX ? .left : .right
        }
        guard let nativeTarget = counterpart(of: target, beside: source) else { return }
        moveItem(source, beside: nativeTarget, side: side)
    }

    private func menuBarDropTarget(at point: CGPoint, imageFrame: CGRect?) -> (CGPoint, CGRect, StatusWindow)? {
        guard let context = shelfDropContext else { return nil }
        let pointer = quartzPoint(point)
        let image = imageFrame.map {
            CGRect(x: $0.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.maxY,
                   width: $0.width, height: $0.height)
        }
        let shelf = panel.map {
            CGRect(x: $0.frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.frame.maxY,
                   width: $0.frame.width, height: $0.frame.height)
        }
        guard let drop = StatusDragGeometry.menuBarDropPoint(pointer: pointer, image: image,
                                                            bar: context.bar, trigger: context.trigger.frame, shelf: shelf) else { return nil }
        return (drop, context.bar, context.trigger)
    }

    private func currentShelfDropContext() -> (bar: CGRect, trigger: StatusWindow)? {
        guard let trigger = visibleTrigger(),
              let bar = NSScreen.screens.compactMap({ backdrop.background(for: $0)?.barFrame }).first(where: {
                  $0.contains(CGPoint(x: trigger.frame.midX, y: trigger.frame.midY))
              }) else { return nil }
        return (bar, trigger)
    }

    private func reorderShelfItem(_ id: UInt32, beside target: UInt32, before: Bool) {
        let reordered = ShelfOrder.moving(id, beside: target, before: before, in: items.map(\.id))
        guard reordered != items.map(\.id) else { return }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = reordered.compactMap { byID[$0] }
        let currentKeys = items.map(\.orderKey).filter { !$0.isEmpty }
        let currentSet = Set(currentKeys)
        savedShelfOrder = currentKeys + savedShelfOrder.filter { !currentSet.contains($0) }
        UserDefaults.standard.set(savedShelfOrder.filter { !$0.hasPrefix("session:") }, forKey: "shelfItemOrder")
        message = ""
        trigger.button?.toolTip = "Menu Bar Bar. Click to open, right-click for options."
    }

    private func controlOnRow(of source: StatusWindow, divider: Bool) -> StatusWindow? {
        let title = divider ? "Tray.Divider" : "Tray.Trigger"
        let control = divider ? self.divider : self.trigger
        let expectedWidth = MenuItems.frame(of: control?.button?.window, title: title)?.width
        let candidates = StatusWindow.all().filter {
            abs($0.frame.midY - source.frame.midY) < 3 &&
            ($0.title == title || ($0.title == Bundle.main.bundleIdentifier &&
                abs($0.frame.width - (expectedWidth ?? -1)) < 1))
        }
        return candidates.first(where: { $0.title == title }) ?? (candidates.count == 1 ? candidates.first : nil)
    }

    private func counterpart(of target: StatusWindow, beside source: StatusWindow) -> StatusWindow? {
        if abs(target.frame.midY - source.frame.midY) < 3 { return target }
        if target.id == visibleTrigger()?.id { return controlOnRow(of: source, divider: false) }
        let sourceApp = sources.first { abs($0.frame.midX - target.frame.midX) < 3 && abs($0.frame.midY - target.frame.midY) < 3 }
        let bundleID = sourceApp.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier }
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: target.title).first?.bundleIdentifier
        guard let bundleID else { return nil }
        let matches = StatusWindow.all().filter {
            $0.title == bundleID && abs($0.frame.midY - source.frame.midY) < 3 && abs($0.frame.width - target.frame.width) < 1
        }
        // Multiple identical extras from one app are ambiguous. Leave the item
        // in its original location instead of selecting the wrong neighbor.
        return matches.count == 1 ? matches.first : nil
    }

    func bundleStatusItem(_ original: StatusWindow) {
        guard let item = StatusWindow.current(original.id), item.pid == original.pid,
              let target = controlOnRow(of: item, divider: true) else { return }
        moveItem(item, beside: target, side: .left) { [weak self] in
            guard let self else { return }
            if self.isArranging {
                UserDefaults.standard.set(true, forKey: "hasFinishedSetup")
                self.isArranging = false
                self.updateDivider()
            }
            self.message = ""
        }
    }

    func moveToMenuBar(_ item: MenuItem) {
        guard moveTask == nil, let source = StatusWindow.current(item.id),
              let target = controlOnRow(of: source, divider: false) else { return }
        moveItem(source, beside: target, side: .right)
    }

    private func moveItem(_ item: StatusWindow, beside target: StatusWindow, side: StatusItemMover.Side,
                          afterMove: (() -> Void)? = nil) {
        guard moveTask == nil else { return }
        movingItemID = item.id
        trigger.button?.highlight(true)
        scanTask?.cancel()
        scanTask = nil
        sourceTransitionItems = items
        if !items.contains(where: { $0.id == item.id }),
           let source = sources.first(where: { abs($0.frame.midX - item.frame.midX) < 3 && abs($0.frame.midY - item.frame.midY) < 3 }) {
            sourceTransitionItems.append(MenuItem(id: item.id, pid: item.pid,
                sourcePID: source.pid, name: source.name, frame: item.frame, image: nil, isLiveImage: false))
        }
        moveTask = Task { [weak self] in
            var succeeded = false
            var failure: String?
            do {
                try await StatusItemMover.move(item, beside: target, side: side)
                succeeded = !Task.isCancelled
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
            guard let self else { return }
            self.movingItemID = nil
            self.moveTask = nil
            self.trigger.button?.highlight(false)
            self.refresh()
            if succeeded {
                self.message = ""
                self.trigger.button?.toolTip = "Menu Bar Bar. Click to open, right-click for options."
                afterMove?()
            }
            else if let failure {
                self.message = failure
                self.trigger.button?.toolTip = failure
                Logger(subsystem: "com.alfonsokim.tray", category: "StatusMove").error("Move failed: \(failure, privacy: .public)")
            }
        }
    }

    func activate(_ item: MenuItem) {
        guard movingItemID == nil, shelfDraggedItemID == nil else { return }
        guard accessibilityAccess else {
            message = "Enable Accessibility so Menu Bar Bar can open this app’s menu."
            showSettings()
            return
        }
        guard let panel, let content = panel.contentView, shelfPresented else { return }
        activationTask?.cancel()
        let revision = shelfPresentationRevision
        let local = itemFrames[item.id] ?? CGRect(x: panel.frame.width / 2 - rowHeight / 2,
                                                  y: shelfJoinHeight, width: rowHeight, height: rowHeight)
        let anchor = CGRect(x: panel.frame.minX + local.minX, y: panel.frame.maxY - local.maxY,
                            width: local.width, height: local.height)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let quartzAnchor = CGRect(x: anchor.minX, y: primaryTop - anchor.maxY, width: anchor.width, height: anchor.height)
        let quartzDisplay = CGRect(x: screenFrame.minX, y: primaryTop - screenFrame.maxY,
                                   width: screenFrame.width, height: screenFrame.height)
        activationTask = Task { [weak self] in
            let entries = await BundledMenuAccess.menu(pid: item.sourcePID, frame: item.frame)
            guard let self, !Task.isCancelled, self.shelfPresented,
                  revision == self.shelfPresentationRevision else { return }
            if case .menu(let entries) = entries {
                self.isPresentingBundledMenu = true
                let selected = self.bundledMenuPresenter.show(entries, at: anchor, in: content) { [weak self] entry in
                    guard let self else { return }
                    self.commandTask?.cancel()
                    self.commandTask = Task { [weak self] in
                        let performed = await BundledMenuAccess.perform(pid: item.sourcePID, frame: item.frame, entry: entry)
                        guard !Task.isCancelled, let self else { return }
                        if !performed {
                            self.message = "This menu changed or the app did not accept the command. Open its menu again."
                            self.showSettings()
                        }
                    }
                }
                self.isPresentingBundledMenu = false
                guard !Task.isCancelled else { return }
                if !selected && !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hideShelf()
                }
            } else if case .noMenu = entries {
                let activation = await BundledMenuAccess.press(pid: item.sourcePID, frame: item.frame,
                                                               anchor: quartzAnchor, display: quartzDisplay)
                guard !Task.isCancelled else { return }
                self.activePopupID = activation.windowID
                if !activation.performed {
                    self.message = "This app does not expose a menu or action that Menu Bar Bar can open while its icon is bundled."
                    self.showSettings()
                }
            } else {
                self.message = "This app’s menu is not available yet. Its icon has stayed bundled. Try opening it again."
                self.showSettings()
            }
        }
    }

    @objc func showSettings() {
        guard moveTask == nil, !isGeneratedMoveClick else { return }
        refresh()
        if settings == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Menu Bar Bar"
            window.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: SetupView(controller: self))
            window.contentView = content
            window.setContentSize(content.fittingSize)
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        MenuItems.openPrivacy("Privacy_Accessibility")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch { message = error.localizedDescription }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let arrange = NSMenuItem(title: "Arrange Icons…", action: #selector(arrangeFromMenu), keyEquivalent: "")
        arrange.target = self
        menu.addItem(arrange)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Menu Bar Bar (restore all icons)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        if let button = trigger.button { menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY), in: button) }
    }

    @objc private func arrangeFromMenu() { arrange() }
}

final class ShelfPanel: NSPanel {
    let materialBridge = MenuMaterialBridge()

    override func orderOut(_ sender: Any?) {
        materialBridge.orderOut(sender)
        super.orderOut(sender)
    }

    override func close() {
        materialBridge.close()
        super.close()
    }

    override var canBecomeKey: Bool { true }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        title = "Menu Bar Bar Shelf"
        isOpaque = false
        // A separate window shadow creates a horizontal seam across the join.
        hasShadow = false
        level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}
