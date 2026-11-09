import CoreGraphics

public struct ShelfDragCell: Sendable {
    public let id: UInt32
    public let frame: CGRect
    public init(id: UInt32, frame: CGRect) { self.id = id; self.frame = frame }
}

public struct ShelfReorderSlot: Equatable, Sendable {
    public let targetID: UInt32
    public let onLeft: Bool
    public let indicatorX: CGFloat
}

public enum StatusDragGeometry {
    /// Cell and pointer coordinates share the shelf's top-left origin.
    public static func reorderSlot(for sourceID: UInt32, at point: CGPoint,
                                   viewport: CGRect, cells: [ShelfDragCell]) -> ShelfReorderSlot? {
        guard viewport.contains(point), cells.contains(where: { $0.id == sourceID }) else { return nil }
        let neighbors = cells.filter { $0.id != sourceID && $0.frame.intersects(viewport) }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let last = neighbors.last else { return nil }
        let next = neighbors.first { point.x < $0.frame.midX }
        let target = next ?? last
        let x = next == nil ? target.frame.maxX : target.frame.minX
        return ShelfReorderSlot(targetID: target.id, onLeft: next != nil,
                                indicatorX: min(viewport.maxX, max(viewport.minX, x)))
    }

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= 4
    }

    public static func isMenuBarDrop(_ point: CGPoint, bar: CGRect, trigger: CGRect) -> Bool {
        menuBarDropPoint(pointer: point, image: nil, bar: bar, trigger: trigger) != nil
    }

    /// Accept the cursor or a meaningful overlap of the drag image. Return a
    /// point on the row's center line, independent of the drag's grab offset.
    public static func menuBarDropPoint(pointer: CGPoint, image: CGRect?, bar: CGRect, trigger: CGRect,
                                       shelf: CGRect? = nil) -> CGPoint? {
        guard !bar.isEmpty else { return nil }
        let pointerInside = pointer.x >= bar.minX && pointer.x < bar.maxX &&
            pointer.y >= bar.minY && pointer.y <= bar.maxY
        let x: CGFloat
        if pointerInside {
            x = pointer.x
        } else if let image, !image.isEmpty {
            // A small upward wobble during horizontal shelf reordering should
            // not remove the item. The image must cross the row by its center.
            if shelf?.contains(pointer) == true && !bar.contains(CGPoint(x: image.midX, y: image.midY)) { return nil }
            let overlap = image.intersection(bar)
            guard !overlap.isNull, overlap.width >= 4, overlap.height >= 4 else { return nil }
            x = min(bar.maxX - 1, max(bar.minX, image.midX))
        } else {
            return nil
        }
        let normalized = CGPoint(x: x, y: bar.midY)
        guard !trigger.contains(normalized) else { return nil }
        return normalized
    }

    /// Native dragging can hold the image by its top rather than its center.
    /// Preserve that grab offset while aligning the icon with the target row.
    public static func releaseY(grabPoint: CGPoint, draggedFrame: CGRect, target: CGRect) -> CGFloat? {
        guard !draggedFrame.isEmpty, !target.isEmpty else { return nil }
        let offset = grabPoint.y - draggedFrame.midY
        let y = target.midY + offset
        guard abs(offset) <= draggedFrame.height / 2 + 1,
              y >= target.minY - 1, y <= target.maxY + 1 else { return nil }
        return min(target.maxY, max(target.minY, y))
    }

    /// Place the dragged image beside the neighbour using the observed grab
    /// offset. A top-left grab needs the whole icon width on a left-side drop.
    public static func releasePoint(grabPoint: CGPoint, draggedFrame: CGRect,
                                    target: CGRect, onLeft: Bool) -> CGPoint? {
        guard let y = releaseY(grabPoint: grabPoint, draggedFrame: draggedFrame, target: target) else { return nil }
        let offset = grabPoint.x - draggedFrame.minX
        guard offset >= -1, offset <= draggedFrame.width + 1 else { return nil }
        let origin = onLeft ? target.minX - draggedFrame.width : target.maxX
        return CGPoint(x: origin + min(draggedFrame.width, max(0, offset)), y: y)
    }

    public static func isBeside(source: CGRect, target: CGRect, onLeft: Bool) -> Bool {
        abs(source.midY - target.midY) < 3 &&
            abs(onLeft ? source.maxX - target.minX : source.minX - target.maxX) <= 2
    }
}
