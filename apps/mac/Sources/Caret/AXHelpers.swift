import ApplicationServices
import AppKit

enum AXHelpers {
    static func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        return value as? String
    }

    static func hasAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let names = names as? [String]
        else { return false }
        return names.contains(attribute as String)
    }

    static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let focused = copyElement(appElement, kAXFocusedUIElementAttribute as CFString) {
            return focused
        }
        let system = AXUIElementCreateSystemWide()
        if let focused = copyElement(system, kAXFocusedUIElementAttribute as CFString) {
            return focused
        }
        return copyElement(appElement, kAXFocusedWindowAttribute as CFString)
    }

    static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }

        return cocoaRect(fromAX: CGRect(origin: position, size: size))
    }

    static func selectedTextBounds(_ element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef
        else { return nil }

        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        )
        guard result == .success, let boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width > 0 || rect.height > 0 else { return nil }
        return cocoaRect(fromAX: rect)
    }

    static func cocoaRect(fromAX axRect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(
            x: axRect.origin.x,
            y: primaryHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    static func clamp(_ rect: CGRect, to visible: CGRect) -> CGRect {
        var result = rect
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width - 4 }
        if result.minX < visible.minX { result.origin.x = visible.minX + 4 }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height - 4 }
        if result.minY < visible.minY { result.origin.y = visible.minY + 4 }
        return result
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func isTrusted() -> Bool {
        AccessibilityTrust.isTrusted()
    }

    static func openAccessibilitySettings() {
        AccessibilityTrust.openSettings()
    }

    static func selectedTextRange(_ element: AXUIElement) -> NSRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef
        else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }
        guard cfRange.location >= 0, cfRange.length >= 0 else { return nil }
        return NSRange(location: cfRange.location, length: cfRange.length)
    }

    static func fieldValue(_ element: AXUIElement) -> String? {
        if let value = stringValue(element, kAXValueAttribute as CFString), !value.isEmpty {
            return value
        }
        return stringValue(element, kAXSelectedTextAttribute as CFString)
    }

    @discardableResult
    static func setFieldValue(_ element: AXUIElement, _ value: String) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        return result == .success
    }

    /// Inserts `text` at the current caret (end of the selected range).
    @discardableResult
    static func insertAtCaret(_ element: AXUIElement, text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard let value = fieldValue(element) else { return false }
        guard let range = selectedTextRange(element) else { return false }

        let nsValue = value as NSString
        let insertLocation = min(range.location + range.length, nsValue.length)
        let updated = nsValue.replacingCharacters(
            in: NSRange(location: insertLocation, length: 0),
            with: text
        )
        guard setFieldValue(element, updated) else { return false }

        var newRange = CFRange(location: insertLocation + (text as NSString).length, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &newRange) else { return true }
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        return true
    }

    static func caretBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = selectedTextRange(element) else { return nil }
        var cfRange = CFRange(location: range.location, length: max(range.length, 0))
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsRef
        )
        guard result == .success, let boundsRef else { return frame(element) }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return frame(element) }
        return cocoaRect(fromAX: rect)
    }
}
