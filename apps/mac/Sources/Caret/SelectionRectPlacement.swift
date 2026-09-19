import CoreGraphics
import Foundation

/// Turns AX selection bounds into a Cocoa screen rect for trigger placement.
enum SelectionRectPlacement {
    static func screenRect(rawBounds: CGRect?, mouse: CGPoint, fieldFrame: CGRect?) -> CGRect {
        let fallback = CGRect(x: mouse.x - 32, y: mouse.y - 14, width: 64, height: 28)
        guard var rect = rawBounds?.standardized, !rect.isNull, !rect.isInfinite else {
            return fallback
        }

        if let field = fieldFrame?.standardized {
            rect = offsetLocalBoundsIfNeeded(rect, fieldFrame: field)
        }

        guard isPlausible(rect, near: mouse) else { return fallback }
        return rect
    }

    /// Web views often return range bounds relative to the web area, not the screen.
    static func offsetLocalBoundsIfNeeded(_ bounds: CGRect, fieldFrame: CGRect) -> CGRect {
        if fieldFrame.insetBy(dx: -24, dy: -24).contains(bounds) {
            return bounds
        }
        let looksLocal = bounds.origin.x >= 0
            && bounds.origin.y >= 0
            && bounds.maxX <= fieldFrame.width + 8
            && bounds.maxY <= fieldFrame.height + 8
        guard looksLocal else { return bounds }
        return bounds.offsetBy(dx: fieldFrame.origin.x, dy: fieldFrame.origin.y)
    }

    static func isPlausible(_ rect: CGRect, near mouse: CGPoint) -> Bool {
        if rect.width < 1 && rect.height < 1 { return false }
        if rect.insetBy(dx: -120, dy: -80).contains(mouse) { return true }
        if rect.maxX < 320 && mouse.x > rect.maxX + 100 { return false }
        return rect.width >= 8 || rect.height >= 8
    }
}
