import XCTest

final class HistoryDebugTests: XCTestCase {
    func testCommandUsesProjectRootAndLease() {
        let root = URL(fileURLWithPath: "/tmp/caret-root")
        XCTAssertEqual(
            HistoryDebug.command(projectRoot: root),
            [
                "python3",
                "-m",
                "caret",
                "history-debug",
                "--lease",
                "/tmp/caret-root/.local/screenpipe-lease.json",
            ]
        )
    }

    func testFormatShowsTwoSnippetsAndSectionErrors() {
        let payload: [String: Any] = [
            "n": 2,
            "windows": [
                "ok": true,
                "items": [
                    [
                        "app": "Safari",
                        "title": "Inbox",
                        "timestamp": "2026-09-19T12:02:00-05:00",
                        "text": "newer",
                    ],
                    [
                        "app": "Cursor",
                        "title": "hackathon",
                        "timestamp": "2026-09-19T12:01:00-05:00",
                        "text": "hello",
                    ],
                ],
            ],
            "minutes": [
                "ok": false,
                "error": "no screenpipe history in the requested minutes",
                "items": [],
            ],
            "clipboard": [
                "ok": true,
                "items": [
                    [
                        "app": "Safari",
                        "title": "Inbox",
                        "timestamp": "2026-09-19T12:02:00-05:00",
                        "text": "copied",
                    ],
                ],
            ],
        ]
        let text = HistoryDebug.format(payload)
        XCTAssertTrue(text.contains("Windows"))
        XCTAssertTrue(text.contains("Minutes"))
        XCTAssertTrue(text.contains("Clipboard"))
        XCTAssertTrue(text.contains("Safari"))
        XCTAssertTrue(text.contains("Inbox"))
        XCTAssertTrue(text.contains("newer"))
        XCTAssertTrue(text.contains("Cursor"))
        XCTAssertTrue(text.contains("hello"))
        XCTAssertTrue(text.contains("copied"))
        XCTAssertTrue(text.contains("no screenpipe history in the requested minutes"))
    }

    func testMissingProjectRootMessage() {
        XCTAssertFalse(HistoryDebug.missingRootMessage.isEmpty)
        XCTAssertEqual(HistoryDebug.load(projectRoot: nil), HistoryDebug.missingRootMessage)
    }
}
