import CoreGraphics
import Foundation

/// Resolves a focused input caret into a Cocoa screen anchor (Cursor, web fields, native text).
enum InputRectPlacement {
    static func screenRect(rawCaret: CGRect, mouse: CGPoint, fieldFrame: CGRect?) -> CGRect {
        let fallback = CGRect(x: mouse.x - 8, y: mouse.y - 14, width: 16, height: 28)
        var caret = rawCaret.standardized

        if let field = fieldFrame?.standardized {
            caret = SelectionRectPlacement.offsetLocalBoundsIfNeeded(caret, fieldFrame: field)
        }

        guard isPlausible(caret, near: mouse) else { return fallback }
        if caret.width <= 2 {
            let centerX = abs(mouse.y - caret.midY) <= 60 ? mouse.x : caret.minX
            return CGRect(x: centerX - 8, y: caret.midY - 14, width: 16, height: 28)
        }
        return caret
    }

    static func isPlausible(_ caret: CGRect, near mouse: CGPoint) -> Bool {
        if caret.isNull || caret.isInfinite { return false }
        if caret.insetBy(dx: -100, dy: -60).contains(mouse) { return true }
        let distance = hypot(caret.midX - mouse.x, caret.midY - mouse.y)
        if distance <= 220 { return true }
        // AX often pins the caret to a window corner while the pointer stays in the field.
        if caret.maxX > 1200 && mouse.x < caret.minX - 80 { return false }
        if caret.minY < 80 && mouse.y > caret.maxY + 120 { return false }
        return caret.width >= 8 || caret.height >= 8
    }
}
