import AppKit
import QuartzCore
import TrayCore

/// Lives inside the native button so it follows menu-bar visibility and clicks.
final class ChevronView: NSView {
    private let strokes = CAShapeLayer()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        wantsLayer = true
        strokes.frame = bounds
        strokes.fillColor = nil
        strokes.lineWidth = 1.5
        strokes.lineCap = .round
        strokes.lineJoin = .round
        layer?.addSublayer(strokes)
        setAccessibilityElement(false)
        updateStrokeColor()
        setOpen(false, animated: false)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStrokeColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        strokes.contentsScale = window?.backingScaleFactor ?? 2
        updateStrokeColor()
    }

    func setOpen(_ open: Bool, animated: Bool) {
        let path = CGMutablePath()
        path.addLines(between: ChevronGeometry.points(progress: open ? 1 : 0, center: CGPoint(x: 9, y: 9))
            .map { CGPoint(x: $0.x, y: 18 - $0.y) })
        let current = strokes.presentation()?.path ?? strokes.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokes.path = path
        CATransaction.commit()
        strokes.removeAnimation(forKey: "direction")
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let current else { return }
        let morph = CABasicAnimation(keyPath: "path")
        morph.fromValue = current
        morph.toValue = path
        morph.duration = 0.18
        morph.timingFunction = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
        strokes.add(morph, forKey: "direction")
    }

    private func updateStrokeColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            strokes.strokeColor = NSColor.labelColor.cgColor
            CATransaction.commit()
        }
    }
}
