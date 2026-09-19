import XCTest

final class TypingPrefixLogicTests: XCTestCase {
    func testPrefersCapturedWhenLongerAndAxIsPrefix() {
        let result = TypingPrefixLogic.effectivePrefix(
            axPrefix: "Hi, my",
            capturedPrefix: "Hi, my name is"
        )
        XCTAssertEqual(result, "Hi, my name is")
    }

    func testUsesAxWhenLonger() {
        let result = TypingPrefixLogic.effectivePrefix(
            axPrefix: "please pull",
            capturedPrefix: "please"
        )
        XCTAssertEqual(result, "please pull")
    }

    func testCapturedWhenAxEmpty() {
        XCTAssertEqual(
            TypingPrefixLogic.effectivePrefix(axPrefix: nil, capturedPrefix: "hello"),
            "hello"
        )
    }
}
