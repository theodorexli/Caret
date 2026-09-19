import CoreGraphics
import XCTest
@testable import Caret

final class InputRectPlacementTests: XCTestCase {
    func testUsesMouseWhenCaretIsStuckInCorner() {
        let cornerCaret = CGRect(x: 1400, y: 40, width: 0, height: 18)
        let mouse = CGPoint(x: 520, y: 680)
        let resolved = InputRectPlacement.screenRect(
            rawCaret: cornerCaret,
            mouse: mouse,
            fieldFrame: CGRect(x: 400, y: 620, width: 520, height: 120)
        )
        XCTAssertTrue(resolved.contains(mouse))
    }

    func testExpandsZeroWidthCaretAlongLine() {
        let caret = CGRect(x: 300, y: 400, width: 0, height: 20)
        let mouse = CGPoint(x: 310, y: 410)
        let resolved = InputRectPlacement.screenRect(rawCaret: caret, mouse: mouse, fieldFrame: nil)
        XCTAssertGreaterThan(resolved.width, 8)
        XCTAssertTrue(resolved.contains(mouse))
    }
}
