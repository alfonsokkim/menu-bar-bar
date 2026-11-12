import AppKit
import QuartzCore
import Testing
@testable import Tray

@MainActor @Test func chevronStaysVisibleAndLeavesClicksOnTheNativeButton() throws {
    _ = NSApplication.shared
    let button = NSButton(frame: CGRect(x: 0, y: 0, width: 28, height: 30))
    let chevron = ChevronView()
    chevron.frame.origin = CGPoint(x: 5, y: 6)
    button.addSubview(chevron)
    let strokes = try #require(chevron.layer?.sublayers?.first as? CAShapeLayer)
    let down = try #require(strokes.path)
    chevron.setOpen(true, animated: false)
    let up = try #require(strokes.path)
    #expect(!CFEqual(down, up))
    #expect(up.boundingBox == down.boundingBox)
    #expect(strokes.opacity == 1)
    #expect((strokes.strokeColor?.alpha ?? 0) > 0.5)
    #expect(strokes.lineWidth == 1.5)
    #expect(chevron.hitTest(CGPoint(x: 9, y: 9)) == nil)
    #expect(button.hitTest(CGPoint(x: 14, y: 15)) === button)
    chevron.setOpen(false, animated: false)
    #expect(CFEqual(strokes.path, down))
    #expect(strokes.animationKeys()?.isEmpty != false)
}

@MainActor @Test func chevronReversalStartsAtItsCurrentPathAndImmediateDismissalSettlesIt() throws {
    _ = NSApplication.shared
    let chevron = ChevronView()
    let strokes = try #require(chevron.layer?.sublayers?.first as? CAShapeLayer)
    let down = try #require(strokes.path)
    chevron.setOpen(true, animated: true)
    let current = try #require(strokes.presentation()?.path ?? strokes.path)
    chevron.setOpen(false, animated: true)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        #expect(strokes.animationKeys()?.isEmpty != false)
    } else {
        let morph = try #require(strokes.animation(forKey: "direction") as? CABasicAnimation)
        let from = try #require(morph.fromValue)
        #expect(CFEqual(from as CFTypeRef, current))
        #expect(morph.duration == 0.18)
        #expect(strokes.animationKeys() == ["direction"])
    }
    chevron.setOpen(false, animated: false)
    #expect(CFEqual(strokes.path, down))
    #expect(strokes.animationKeys()?.isEmpty != false)
    #expect(strokes.opacity == 1)
}
