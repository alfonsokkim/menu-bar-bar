import AppKit
import SwiftUI
import TrayCore

enum ChevronArtwork {
    static func image(hidden: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        if !hidden {
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            for stroke in ChevronGeometry.strokes(phase: 0, center: CGPoint(x: 9, y: 9), travel: 0) {
                path.move(to: CGPoint(x: stroke.start.x, y: 18 - stroke.start.y))
                path.line(to: CGPoint(x: stroke.end.x, y: 18 - stroke.end.y))
            }
            path.stroke()
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Open Menu Bar Bar"
        return image
    }


}

private struct FallingChevron: Shape {
    var phase: CGFloat
    var menuHeight: CGFloat
    var travel: CGFloat
    var originX: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        for stroke in ChevronGeometry.strokes(phase: phase, center: CGPoint(x: originX, y: menuHeight / 2), travel: travel) {
            path.move(to: stroke.start)
            path.addQuadCurve(to: stroke.end, control: stroke.control)
        }
        return path
    }
}

private struct ChevronStrokes: View, Animatable {
    var phase: CGFloat
    let menuHeight: CGFloat
    let rowHeight: CGFloat
    let originX: CGFloat
    let foreground: Color

    nonisolated var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        FallingChevron(phase: phase, menuHeight: menuHeight,
                       travel: (menuHeight / 2 + rowHeight * 0.15) / 0.36,
                       originX: originX)
            .stroke(foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .opacity(Double(ChevronGeometry.opacity(phase: phase)))
    }
}

struct ChevronSplashView: View {
    @ObservedObject var controller: TrayController

    var body: some View {
        ChevronStrokes(phase: controller.chevronPhase, menuHeight: controller.chevronMenuHeight,
                       rowHeight: controller.rowHeight, originX: controller.chevronOriginX,
                       foreground: controller.chevronForeground)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// A small, transparent overlay lets the strokes cross the menu-bar boundary.
/// It never takes focus or intercepts clicks on the real menu bar underneath.
final class ChevronPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Menu Bar Bar Chevron Animation"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}
