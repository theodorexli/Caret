import CoreGraphics
import XCTest
@testable import Caret

final class SelectionRectPlacementTests: XCTestCase {
    func testOffsetsLocalWebBoundsByFieldOrigin() {
        let field = CGRect(x: 180, y: 120, width: 900, height: 700)
        let local = CGRect(x: 40, y: 200, width: 260, height: 18)
        let resolved = SelectionRectPlacement.screenRect(
            rawBounds: local,
            mouse: CGPoint(x: 500, y: 330),
            fieldFrame: field
        )
        XCTAssertEqual(resolved, local.offsetBy(dx: field.origin.x, dy: field.origin.y))
    }

    func testRejectsZeroXStripWhenMouseIsFarRight() {
        let bogus = CGRect(x: 0, y: 400, width: 12, height: 16)
        let mouse = CGPoint(x: 720, y: 410)
        let resolved = SelectionRectPlacement.screenRect(
            rawBounds: bogus,
            mouse: mouse,
            fieldFrame: CGRect(x: 100, y: 100, width: 1000, height: 800)
        )
        XCTAssertTrue(resolved.contains(mouse))
    }

    func testUsesMouseFallbackWhenBoundsMissing() {
        let mouse = CGPoint(x: 300, y: 500)
        let resolved = SelectionRectPlacement.screenRect(rawBounds: nil, mouse: mouse, fieldFrame: nil)
        XCTAssertTrue(resolved.contains(mouse))
    }
}
