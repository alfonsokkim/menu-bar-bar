import AppKit
import ApplicationServices
import Testing
@testable import Tray

private actor RoleReadGate {
    private var readers: [CheckedContinuation<Bool?, Never>] = []
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var reads = 0

    func read() async -> Bool? {
        reads += 1
        return await withCheckedContinuation { continuation in
            readers.append(continuation)
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if reads > 0 { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(_ result: Bool?) {
        let waiting = readers
        readers.removeAll()
        for reader in waiting { reader.resume(returning: result) }
    }
}

@MainActor @Test func menuTitleNotificationBurstsShareOneReadAndStopRejectsLateResults() async throws {
    let gate = RoleReadGate()
    let element = AXUIElementCreateApplication(10003)
    var events: [MenuBarTitleEvent] = []
    let callback = MenuBarTitleObservation.Callback(
        app: AXUIElementCreateApplication(10001), menu: AXUIElementCreateApplication(10002), titles: [],
        classify: { _ in await gate.read() }, notify: { events.append($0) })
    for _ in 0..<1000 { callback.receive([element], notification: kAXLayoutChangedNotification as CFString) }
    let worker = try #require(callback.worker)
    await gate.waitUntilStarted()
    for _ in 0..<1000 { callback.receive([element], notification: kAXLayoutChangedNotification as CFString) }
    #expect(await gate.reads == 1)
    callback.stop()
    callback.receive([AXUIElementCreateApplication(10004)], notification: kAXLayoutChangedNotification as CFString)
    #expect(worker.isCancelled)
    await gate.finish(true)
    await worker.value
    #expect(await gate.reads == 1)
    #expect(events.isEmpty)
    #expect(callback.worker == nil)
}

@MainActor @Test func menuTitleQueueOverflowFallsBackOnceAndCancelsItsReader() async throws {
    let gate = RoleReadGate()
    var events: [MenuBarTitleEvent] = []
    let callback = MenuBarTitleObservation.Callback(
        app: AXUIElementCreateApplication(10001), menu: AXUIElementCreateApplication(10002), titles: [],
        classify: { _ in await gate.read() }, notify: { events.append($0) })
    callback.receive([AXUIElementCreateApplication(10003)], notification: kAXLayoutChangedNotification as CFString)
    let worker = try #require(callback.worker)
    await gate.waitUntilStarted()
    for pid in 10004..<10104 {
        callback.receive([AXUIElementCreateApplication(pid_t(pid))], notification: kAXLayoutChangedNotification as CFString)
    }
    #expect(events == [.unsupportedLayout])
    #expect(worker.isCancelled)
    await gate.finish(true)
    await worker.value
    #expect(await gate.reads == 1)
    #expect(events == [.unsupportedLayout])
    #expect(callback.worker == nil)
}
