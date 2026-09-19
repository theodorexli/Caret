import XCTest
#if SWIFT_PACKAGE
@testable import Caret
#endif

final class SkillActionInputTests: XCTestCase {
    func testTranslatePrefersSelectionOverClipboard() {
        let text = SkillActionInput.sourceText(
            actionID: "translate",
            selectedText: "Bonjour",
            caretLine: "ignored line",
            clipboard: "clipboard text"
        )
        XCTAssertEqual(text, "Bonjour")
    }

    func testTranslateUsesClipboardWhenNothingIsSelected() {
        let text = SkillActionInput.sourceText(
            actionID: "translate",
            selectedText: "  ",
            caretLine: nil,
            clipboard: "clipboard text"
        )
        XCTAssertEqual(text, "clipboard text")
    }

    func testTranslateIgnoresCaretLineWhenNothingIsSelected() {
        let text = SkillActionInput.sourceText(
            actionID: "translate",
            selectedText: "",
            caretLine: "current line in the field",
            clipboard: "clipboard text"
        )
        XCTAssertEqual(text, "clipboard text")
    }

    func testTranslateReturnsNilWhenSelectionAndClipboardAreEmpty() {
        XCTAssertNil(
            SkillActionInput.sourceText(
                actionID: "translate",
                selectedText: "",
                caretLine: "current line",
                clipboard: "  "
            )
        )
    }

    func testOtherGatewaySkillStillUsesCaretLineWhenNothingIsSelected() {
        let text = SkillActionInput.sourceText(
            actionID: "summarize",
            selectedText: "",
            caretLine: "current line in the field",
            clipboard: "clipboard text"
        )
        XCTAssertEqual(text, "current line in the field")
    }

    func testTranslateLiveEmptySelectionDoesNotReuseRememberedText() {
        let live = target(selected: "")
        let remembered = target(selected: "old selection")
        XCTAssertNil(
            SkillActionInput.translateTarget(
                lastTarget: live,
                panelContextTarget: remembered,
                rememberedSelection: remembered
            )
        )
    }

    func testTranslateUsesRememberedSelectionWhenLastTargetIsMissing() {
        let remembered = target(selected: "selected phrase")
        let chosen = SkillActionInput.translateTarget(
            lastTarget: nil,
            panelContextTarget: nil,
            rememberedSelection: remembered
        )
        XCTAssertEqual(chosen?.selectedText, "selected phrase")
    }

    private func target(selected: String) -> SelectionTarget {
        SelectionTarget(
            kind: selected.isEmpty ? .input : .selection,
            selectedText: selected,
            screenRect: .zero,
            mouseLocation: .zero,
            sourceApp: "Notes",
            fieldContext: nil,
            focusedProcessID: 1,
            axRole: "AXTextArea",
            axSubrole: ""
        )
    }
}
