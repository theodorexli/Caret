import AppKit
import CompletionUI

/// KeyType's pinned renderer is shared unchanged; Caret owns offer acceptance.
@MainActor
final class InlineGhostPanel {
    private let overlay = GhostTextOverlayWindow()

    func show(suffix: String, near anchor: CGRect) -> Bool {
        // AX can return the whole field when caret bounds are unavailable.
        // A completion at that field's edge would not be a visible inline offer.
        guard anchor.width <= 4, anchor.height > 0, anchor.height <= 80,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor.origin) })
        else { overlay.hide(); return false }
        overlay.show(
            text: suffix,
            font: .systemFont(ofSize: min(max(anchor.height * 0.75, 11), 24)),
            placement: OverlayPlacement(cursorRect: anchor, fieldRect: screen.visibleFrame),
            textColor: .secondaryLabelColor
        )
        return overlay.isVisible
    }

    func hide() {
        overlay.hide()
    }
}
