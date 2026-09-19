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

    /// Walks focused element, ancestors, and nearby descendants for a text-editable AX node.
    static func focusedTextElement(in app: NSRunningApplication) -> AXUIElement? {
        guard let focused = focusedElement(in: app) else { return nil }
        return bestEditableElement(startingAt: focused) ?? focused
    }

    static func bestEditableElement(startingAt start: AXUIElement) -> AXUIElement? {
        if makeFieldContext(from: start) != nil {
            return start
        }

        var current: AXUIElement? = start
        for _ in 0..<18 {
            guard let element = current else { break }
            if let nested = findEditableDescendant(root: element, maxDepth: 5, nodeBudget: 160) {
                return nested
            }
            if makeFieldContext(from: element) != nil {
                return element
            }
            current = parent(of: element)
        }

        return findEditableDescendant(root: start, maxDepth: 8, nodeBudget: 240)
    }

    private static func findEditableDescendant(
        root: AXUIElement,
        maxDepth: Int,
        nodeBudget: Int
    ) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0

        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > nodeBudget { break }

            if depth > 0, makeFieldContext(from: element) != nil {
                return element
            }
            if depth >= maxDepth { continue }

            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let value
        else { return [] }

        if let elements = value as? [AXUIElement] {
            return elements
        }
        if let array = value as? NSArray {
            var elements: [AXUIElement] = []
            for index in 0 ..< array.count {
                guard let object = array[index] as AnyObject?,
                      CFGetTypeID(object) == AXUIElementGetTypeID()
                else { continue }
                elements.append(object as! AXUIElement)
            }
            return elements
        }
        return []
    }

    static func characterCount(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &value) == .success,
              let value
        else { return nil }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return nil
        }
        return nil
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        copyElement(element, kAXParentAttribute as CFString)
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
        if let selected = stringValue(element, kAXSelectedTextAttribute as CFString), !selected.isEmpty {
            return selected
        }
        guard let range = selectedTextRange(element) else { return nil }
        return composedFieldValue(element, caret: range)
    }

    static func valueForRange(_ element: AXUIElement, range: NSRange) -> String? {
        guard range.length >= 0, range.location >= 0 else { return nil }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForRange" as CFString,
            axRange,
            &valueRef
        )
        guard result == .success, let valueRef else { return nil }
        return valueRef as? String
    }

    static func composedFieldValue(_ element: AXUIElement, caret: NSRange) -> String? {
        let end = caret.location + caret.length
        guard end >= 0 else { return nil }
        if let before = valueForRange(element, range: NSRange(location: 0, length: end)) {
            let after = valueForRange(element, range: NSRange(location: end, length: 16_384)) ?? ""
            return before + after
        }
        return nil
    }

    static func makeFieldContext(from element: AXUIElement) -> FieldTextContext? {
        let range = selectedTextRange(element)

        if let range {
            if let windowed = fieldContextFromCharacterWindow(element, caret: range) {
                return windowed
            }
            if let composed = composedFieldValue(element, caret: range), !composed.isEmpty {
                return FieldTextContext(
                    fullText: composed,
                    selectedRangeLocation: range.location,
                    selectedRangeLength: range.length
                )
            }
            let insert = range.location + range.length
            if let before = valueForRange(element, range: NSRange(location: 0, length: insert)), !before.isEmpty {
                return FieldTextContext(
                    fullText: before,
                    selectedRangeLocation: range.location,
                    selectedRangeLength: range.length
                )
            }
        }

        if let value = stringValue(element, kAXValueAttribute as CFString), !value.isEmpty {
            let caret = range ?? NSRange(location: (value as NSString).length, length: 0)
            let insert = caret.location + caret.length
            if insert > (value as NSString).length,
               let composed = composedFieldValue(element, caret: caret),
               composed.count >= insert
            {
                return FieldTextContext(
                    fullText: composed,
                    selectedRangeLocation: caret.location,
                    selectedRangeLength: caret.length
                )
            }
            return FieldTextContext(
                fullText: value,
                selectedRangeLocation: caret.location,
                selectedRangeLength: caret.length
            )
        }

        return nil
    }

    /// Reads a sliding window of text near the caret (Google Docs / large AXWebArea documents).
    private static func fieldContextFromCharacterWindow(
        _ element: AXUIElement,
        caret: NSRange
    ) -> FieldTextContext? {
        guard let total = characterCount(element), total > 0 else { return nil }
        let insert = min(max(caret.location + caret.length, 0), total)
        guard insert > 0 else { return nil }

        let window = min(1200, insert)
        let start = insert - window
        guard let slice = valueForRange(element, range: NSRange(location: start, length: window)),
              !slice.isEmpty
        else { return nil }

        let caretInSlice = insert - start
        return FieldTextContext(
            fullText: slice,
            selectedRangeLocation: caretInSlice,
            selectedRangeLength: 0
        )
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
        guard let range = selectedTextRange(element) else { return false }

        let insertLocation = range.location + range.length
        if let value = fieldValue(element) {
            let nsValue = value as NSString
            let safeInsert = min(insertLocation, nsValue.length)
            let updated = nsValue.replacingCharacters(
                in: NSRange(location: safeInsert, length: 0),
                with: text
            )
            if setFieldValue(element, updated) {
                setSelectedTextRange(
                    element,
                    range: NSRange(location: safeInsert + (text as NSString).length, length: 0)
                )
                return true
            }
        }

        if let before = valueForRange(element, range: NSRange(location: 0, length: insertLocation)) {
            let after = valueForRange(element, range: NSRange(location: insertLocation, length: 16_384)) ?? ""
            let updated = before + text + after
            if setFieldValue(element, updated) {
                setSelectedTextRange(
                    element,
                    range: NSRange(location: insertLocation + (text as NSString).length, length: 0)
                )
                return true
            }
        }

        return false
    }

    @discardableResult
    static func setSelectedTextRange(_ element: AXUIElement, range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success
    }

    /// Inserts suggestion text at the caret and selects it so it appears inside the field.
    @discardableResult
    static func insertInlineSuggestion(_ element: AXUIElement, suffix: String) -> NSRange? {
        guard !suffix.isEmpty else { return nil }
        guard let range = selectedTextRange(element) else { return nil }
        let insertLocation = range.location + range.length
        guard insertAtCaret(element, text: suffix) else { return nil }
        let suffixRange = NSRange(location: insertLocation, length: (suffix as NSString).length)
        guard setSelectedTextRange(element, range: suffixRange) else { return suffixRange }
        return suffixRange
    }

    @discardableResult
    static func removeRange(_ element: AXUIElement, range: NSRange) -> Bool {
        guard let value = fieldValue(element) else { return false }
        let nsValue = value as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsValue.length else { return false }
        let updated = nsValue.replacingCharacters(in: range, with: "")
        guard setFieldValue(element, updated) else { return false }
        setSelectedTextRange(element, range: NSRange(location: range.location, length: 0))
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
