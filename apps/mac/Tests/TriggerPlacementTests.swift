import XCTest
#if SWIFT_PACKAGE
@testable import Caret
#endif

/// The trigger strip and a Tab completion were both anchored to the caret, so
/// the sparkle and pinned chips sat on top of the completion text. These pin
/// the rule that fixes it: for an input, the strip leaves the caret line.
final class TriggerPlacementTests: XCTestCase {
    private let size = CGSize(width: 160, height: 40)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func target(kind: SelectionTarget.Kind, rect: CGRect) -> SelectionTarget {
        SelectionTarget(
            kind: kind, selectedText: "", screenRect: rect,
            mouseLocation: CGPoint(x: 700, y: 300), sourceApp: "Messages",
            fieldContext: nil, focusedProcessID: 1, axRole: "AXTextArea", axSubrole: nil
        )
    }

    /// The whole strip must sit above the caret line, not merely miss the
    /// caret rect itself: the completion runs rightward along that line.
    func testInputStripClearsTheCaretLine() {
        let caret = CGRect(x: 400, y: 200, width: 1, height: 18)
        let frame = TriggerPlacement.frame(for: target(kind: .input, rect: caret), size: size, visibleFrame: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, caret.maxY, "strip must be above the line the user is typing on")
        XCTAssertFalse(frame.intersects(CGRect(x: caret.minX, y: caret.minY, width: 800, height: caret.height)),
                       "nothing may cover the rest of the caret line, where the completion is drawn")
    }

    /// Selection targets keep the action-on-selection placement.
    func testSelectionStripStaysBesideTheSelection() {
        let selection = CGRect(x: 300, y: 200, width: 120, height: 18)
        let t = target(kind: .selection, rect: selection)
        let frame = TriggerPlacement.frame(for: t, size: size, visibleFrame: screen)
        XCTAssertEqual(frame.minX, t.anchor.x + TriggerPlacement.horizontalGap, accuracy: 0.5)
        XCTAssertEqual(frame.midY, t.anchor.y, accuracy: 0.5)
    }

    /// Without caret geometry there is no line to avoid; fall back to the
    /// mouse-anchored placement rather than inventing one.
    func testInputWithoutCaretGeometryUsesMouseAnchor() {
        let t = target(kind: .input, rect: CGRect(x: 10, y: 10, width: 1, height: 1))
        let frame = TriggerPlacement.frame(for: t, size: size, visibleFrame: screen)
        XCTAssertEqual(frame.midY, t.mouseLocation.y, accuracy: 0.5)
    }

    func testInputStripFlipsLeftAtTheScreenEdge() {
        let caret = CGRect(x: 1400, y: 200, width: 1, height: 18)
        let frame = TriggerPlacement.frame(for: target(kind: .input, rect: caret), size: size, visibleFrame: screen)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, caret.maxY, "flipping left must not drop it back onto the line")
    }
}
