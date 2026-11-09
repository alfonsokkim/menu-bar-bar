import CoreGraphics

public enum ShelfSurface {
    public static let flare: CGFloat = 22

    /// The captured status window already includes macOS's icon spacing.
    public static func cellWidth(itemWidth: CGFloat) -> CGFloat {
        max(1, itemWidth)
    }

    /// Capture a full point above the separator. The window capture API
    /// rejects sub-point heights on Retina displays; the caller keeps only
    /// the bottom physical pixel row, two points clear of the border.
    public static func backgroundSample(barFrame: CGRect, shelfFrame: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let height: CGFloat = 1
        let y = ((barFrame.maxY - 2) * scale).rounded(.down) / scale - height
        return CGRect(x: shelfFrame.minX, y: y, width: shelfFrame.width, height: height)
    }

    /// Coordinates have their origin at the top left, like a SwiftUI Shape.
    /// Horizontal tangents at the top flow out into the menu bar; vertical
    /// tangents at the neck flow into the rounded bottom corners.
    public static func path(in rect: CGRect) -> CGPath {
        let w = rect.width
        let h = rect.height
        let f = min(flare, w / 4)
        let neck = min(22, h * 0.5)
        let r = min(15, h - neck)
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addCurve(to: CGPoint(x: w - f, y: neck),
                   control1: CGPoint(x: w - f * 0.7, y: 0),
                   control2: CGPoint(x: w - f, y: neck * 0.35))
        p.addLine(to: CGPoint(x: w - f, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - f - r, y: h), control: CGPoint(x: w - f, y: h))
        p.addLine(to: CGPoint(x: f + r, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - r), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: f, y: neck))
        p.addCurve(to: .zero, control1: CGPoint(x: f, y: neck * 0.35),
                   control2: CGPoint(x: f * 0.7, y: 0))
        p.closeSubpath()
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return p.copy(using: &transform) ?? p
    }

    /// Grow a neck beneath the trigger, then let its rounded body spread into
    /// the shelf. Only the mask moves; the sampled background stays in place.
    public static func liquidPath(in bounds: CGRect, progress: CGFloat, originX: CGFloat, joinHeight: CGFloat = 0) -> CGPath {
        guard progress > 0 else { return CGMutablePath() }
        let join = min(max(0, joinHeight), bounds.height)
        let rect = CGRect(x: bounds.minX, y: bounds.minY + join, width: bounds.width, height: bounds.height - join)
        if progress == 1 && join == 0 { return path(in: rect) }
        let growth = min(1, progress)
        let ripple = min(0.15, max(0, progress - 1))
        let w = rect.width
        let depth = rect.height * growth * (2 - growth)
        let origin = min(w - min(15, w / 2), max(min(15, w / 2), originX))
        let center = origin + (w / 2 - origin) * growth
        let topHalf = 3 + (w / 2 - 3) * growth * growth
        let finalHalf = w / 2 - min(flare, w / 4)
        let bodyHalf = depth / 2 + (finalHalf - depth / 2) * growth + ripple * flare
        let neck = min(22, depth * 0.5)
        let radius = min(15, bodyHalf, depth - neck)
        let leftTop = max(0, center - topHalf)
        let rightTop = min(w, center + topHalf)
        let leftBody = max(0, center - bodyHalf)
        let rightBody = min(w, center + bodyHalf)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: leftTop, y: -join))
        p.addLine(to: CGPoint(x: rightTop, y: -join))
        p.addLine(to: CGPoint(x: rightTop, y: 0))
        p.addCurve(to: CGPoint(x: rightBody, y: neck),
                   control1: CGPoint(x: rightTop + (rightBody - rightTop) * 0.7, y: 0),
                   control2: CGPoint(x: rightBody, y: neck * 0.35))
        p.addLine(to: CGPoint(x: rightBody, y: depth - radius))
        p.addQuadCurve(to: CGPoint(x: rightBody - radius, y: depth), control: CGPoint(x: rightBody, y: depth))
        p.addLine(to: CGPoint(x: leftBody + radius, y: depth))
        p.addQuadCurve(to: CGPoint(x: leftBody, y: depth - radius), control: CGPoint(x: leftBody, y: depth))
        p.addLine(to: CGPoint(x: leftBody, y: neck))
        p.addCurve(to: CGPoint(x: leftTop, y: 0),
                   control1: CGPoint(x: leftBody, y: neck * 0.35),
                   control2: CGPoint(x: leftTop + (leftBody - leftTop) * 0.7, y: 0))
        p.closeSubpath()
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return p.copy(using: &transform) ?? p
    }

    /// Extend only the panel's top over the native separator. The body and
    /// icons retain their original bounds below the menu bar.
    public static func panelFrame(bodyFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: bodyFrame.minX, y: bodyFrame.minY, width: bodyFrame.width,
               height: bodyFrame.height + 1 / max(1, scale))
    }

    /// Meet the menu bar edge to edge on a physical pixel boundary.
    public static func frame(anchor: CGRect, screen: CGRect, menuBarBottom: CGFloat,
                             bodyWidth: CGFloat, height: CGFloat, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let width = min(screen.width - 16, bodyWidth + flare * 2)
        let x = min(screen.maxX - width - 8, max(screen.minX + 8, anchor.midX - width / 2))
        let top = (menuBarBottom * scale).rounded() / scale
        let h = (height * scale).rounded() / scale
        return CGRect(x: (x * scale).rounded() / scale, y: top - h, width: (width * scale).rounded() / scale, height: h)
    }
}
