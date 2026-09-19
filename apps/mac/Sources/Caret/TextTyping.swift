import AppKit
import CoreGraphics

enum TextTyping {
    /// Posts Unicode text as HID keyboard events (works in Google Docs and other AX-hostile editors).
    @discardableResult
    static func postUnicodeText(_ string: String) -> Bool {
        guard !string.isEmpty else { return true }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        var utf16 = Array(string.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return false }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
