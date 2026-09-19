import ApplicationServices
import AppKit

struct FieldTextContext: Equatable {
    let fullText: String
    let selectedRangeLocation: Int
    let selectedRangeLength: Int

    var insertLocation: Int { selectedRangeLocation + selectedRangeLength }

    var prefix: String {
        let ns = fullText as NSString
        let end = min(max(insertLocation, 0), ns.length)
        let window = 1200
        let start = max(0, end - window)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    var digest: String {
        let tail = prefix.suffix(96)
        return "\(fullText.count)-\(insertLocation)-\(tail.hashValue)"
    }
}

struct SelectionTarget {
    enum Kind {
        case selection
        case input
    }

    var kind: Kind
    var selectedText: String
    var screenRect: CGRect
    var mouseLocation: CGPoint
    var sourceApp: String?
    var fieldContext: FieldTextContext?
    var focusedProcessID: pid_t?
    var axRole: String?
    var axSubrole: String?

    var typingSessionKey: String {
        let pid = focusedProcessID ?? 0
        let role = axRole ?? ""
        let sub = axSubrole ?? ""
        return "\(pid)-\(role)-\(sub)"
    }

    func effectivePrefix(captured: String) -> String {
        TypingPrefixLogic.effectivePrefix(axPrefix: fieldContext?.prefix, capturedPrefix: captured)
    }

    var anchor: CGPoint {
        if screenRect.width > 2, screenRect.height > 2 {
            return CGPoint(x: screenRect.maxX + 6, y: screenRect.midY)
        }
        return mouseLocation
    }
}

final class SelectionMonitor {
    var onChange: ((SelectionTarget?) -> Void)?

    private var timer: Timer?
    private var mouseMonitor: Any?
    private var lastSignature: String?
    private var pendingHide: DispatchWorkItem?
    private var lastMouse = NSEvent.mouseLocation

    private let inputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
        "AXTextInput",
        "AXEditableText",
        "AXWebArea",
        "AXCodeEditor",
    ]

    func refreshNow() {
        lastMouse = NSEvent.mouseLocation
        inspect()
    }

    func start() {
        stop()

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.lastMouse = NSEvent.mouseLocation
                self?.inspect()
            }
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.inspect()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        inspect()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingHide?.cancel()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func inspect() {
        guard AXHelpers.isTrusted() else {
            TypingPrefixCapture.shared.setActiveSession(nil)
            publish(nil)
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            TypingPrefixCapture.shared.setActiveSession(nil)
            publish(nil)
            return
        }

        let mouse = lastMouse
        let element = AXHelpers.focusedTextElement(in: app)
        let role = element.flatMap { AXHelpers.stringValue($0, kAXRoleAttribute as CFString) } ?? ""
        let subrole = element.flatMap { AXHelpers.stringValue($0, kAXSubroleAttribute as CFString) } ?? ""

        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            publish(nil)
            return
        }

        let selected = element.flatMap { AXHelpers.stringValue($0, kAXSelectedTextAttribute as CFString) } ?? ""
        let selectionBounds = element.flatMap { AXHelpers.selectedTextBounds($0) }
        let frame = element.flatMap { AXHelpers.frame($0) }

        let fieldContext = element.flatMap { AXHelpers.makeFieldContext(from: $0) }
        let sessionKey = "\(app.processIdentifier)-\(role)-\(subrole)"
        TypingPrefixCapture.shared.setActiveSession(sessionKey)
        if let prefix = fieldContext?.prefix {
            TypingPrefixCapture.shared.mergeAXPrefix(prefix, sessionKey: sessionKey)
        }

        if !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let screenRect = SelectionRectPlacement.screenRect(
                rawBounds: selectionBounds,
                mouse: mouse,
                fieldFrame: frame
            )
            publish(
                SelectionTarget(
                    kind: .selection,
                    selectedText: selected,
                    screenRect: screenRect,
                    mouseLocation: mouse,
                    sourceApp: app.localizedName,
                    fieldContext: fieldContext,
                    focusedProcessID: app.processIdentifier,
                    axRole: role,
                    axSubrole: subrole
                )
            )
            return
        }

        if isTextInput(role: role, subrole: subrole, element: element) {
            let rawCaret = element.flatMap { AXHelpers.caretBounds($0) }
                ?? frame
                ?? CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
            let screenRect = InputRectPlacement.screenRect(
                rawCaret: rawCaret,
                mouse: mouse,
                fieldFrame: frame
            )
            publish(
                SelectionTarget(
                    kind: .input,
                    selectedText: "",
                    screenRect: screenRect,
                    mouseLocation: mouse,
                    sourceApp: app.localizedName,
                    fieldContext: fieldContext,
                    focusedProcessID: app.processIdentifier,
                    axRole: role,
                    axSubrole: subrole
                )
            )
            return
        }

        TypingPrefixCapture.shared.setActiveSession(nil)

        publish(nil)
    }

    private func isTextInput(role: String, subrole: String, element: AXUIElement?) -> Bool {
        if inputRoles.contains(role) || inputRoles.contains(subrole) {
            return true
        }

        let description = (element.flatMap { AXHelpers.stringValue($0, kAXRoleDescriptionAttribute as CFString) } ?? "")
            .lowercased()
        return description.contains("text field")
            || description.contains("text area")
            || description.contains("search field")
            || description.contains("combo box")
            || description.contains("editor")
            || subrole.lowercased().contains("editor")
    }

    private func publish(_ target: SelectionTarget?) {
        let signature = target.map {
            let captured = TypingPrefixCapture.shared.prefix(for: $0.typingSessionKey)
            let effective = $0.effectivePrefix(captured: captured)
            let tail = effective.suffix(48)
            return "\($0.kind)-\(Int($0.anchor.x))-\(Int($0.anchor.y))-\($0.typingSessionKey)-\(tail.hashValue)"
        } ?? "nil"

        if signature == lastSignature { return }

        if target == nil {
            guard pendingHide == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastSignature = "nil"
                self.pendingHide = nil
                self.onChange?(nil)
            }
            pendingHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            return
        }

        pendingHide?.cancel()
        pendingHide = nil
        lastSignature = signature
        onChange?(target)
    }
}
