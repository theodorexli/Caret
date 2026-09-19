import XCTest
@testable import Caret

final class TriggerButtonGeometryTests: XCTestCase {
    func testClusterNeverCoversFieldAfterScreenClamping() {
        let screen = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        for field in [
            CGRect(x: -1000, y: 300, width: 500, height: 180),
            CGRect(x: -520, y: 300, width: 500, height: 180),
            CGRect(x: -1195, y: 300, width: 1190, height: 180),
            CGRect(x: -1195, y: 45, width: 1190, height: 180),
            CGRect(x: -1195, y: 650, width: 1190, height: 180),
            CGRect(x: -300, y: 300, width: 0, height: 18)
        ] {
            for width in [CGFloat(40), CGFloat(220)] {
                let frame = TriggerButtonGeometry.frame(avoiding: field, size: CGSize(width: width, height: 40), visibleFrame: screen)
                XCTAssertNotNil(frame)
                if let frame {
                    XCTAssertTrue(screen.contains(frame))
                    XCTAssertFalse(frame.intersects(field.insetBy(dx: -8, dy: -8)))
                }
            }
        }
    }

    func testNoRoomHidesInsteadOfCoveringText() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(TriggerButtonGeometry.frame(avoiding: screen, size: CGSize(width: 40, height: 40), visibleFrame: screen))
        XCTAssertNil(TriggerButtonGeometry.frame(avoiding: .zero, size: CGSize(width: 900, height: 40), visibleFrame: screen))
    }

    func testSelectionAnchorUsesHighlightOnly() {
        let selection = CGRect(x: 420, y: 360, width: 280, height: 22)
        let target = SelectionTarget(
            kind: .selection,
            selectedText: "headline",
            screenRect: selection,
            mouseLocation: .zero,
            sourceApp: "Arc",
            fieldContext: nil,
            focusedProcessID: 1,
            axRole: "AXWebArea",
            axSubrole: ""
        )
        XCTAssertEqual(TriggerButtonPlacement.anchorRect(for: target), selection)
    }

    func testInputAvoidRectUsesFieldOnlyForZeroWidthCaretInsideField() {
        let caret = CGRect(x: 420, y: 360, width: 0, height: 18)
        let field = CGRect(x: 400, y: 340, width: 400, height: 80)
        let target = SelectionTarget(
            kind: .input,
            selectedText: "",
            screenRect: caret,
            mouseLocation: .zero,
            sourceApp: "Notes",
            fieldContext: nil,
            focusedProcessID: 1,
            axRole: "AXTextArea",
            axSubrole: ""
        )
        XCTAssertEqual(
            TriggerButtonPlacement.avoidRect(for: target, fieldFrame: field, anchor: caret),
            field
        )
    }

    func testAdjacentFrameSitsBesideComposerAnchor() {
        let anchor = CGRect(x: 480, y: 650, width: 16, height: 28)
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let frame = TriggerButtonGeometry.frame(
            adjacentTo: anchor,
            size: CGSize(width: 220, height: 40),
            visibleFrame: visible
        )
        XCTAssertEqual(frame.minX, anchor.maxX + 6, accuracy: 0.5)
        XCTAssertEqual(frame.midY, anchor.midY, accuracy: 0.5)
    }
}
