import AppKit
import ApplicationServices
import CoreGraphics

/// Rolling keystroke buffer for editors that hide AX text (Cursor Composer, Google Docs).
final class TypingPrefixCapture {
    static let shared = TypingPrefixCapture()

    var onChange: (() -> Void)?

    private var buffers: [String: String] = [:]
    private(set) var activeSessionKey: String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func start() {
        guard eventTap == nil, AXHelpers.isTrusted() else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let capture = Unmanaged<TypingPrefixCapture>.fromOpaque(refcon).takeUnretainedValue()
            capture.handleKeyDown(event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[Caret] Keystroke capture tap unavailable (Accessibility required)")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func setActiveSession(_ key: String?) {
        if let key, let pid = key.split(separator: "-").first.flatMap({ Int32($0) }) {
            let pidBuffer = prefix(for: Self.pidKey(pid))
            if !pidBuffer.isEmpty {
                mergeAXPrefix(pidBuffer, sessionKey: key)
            }
        }
        activeSessionKey = key
    }

    func prefix(for sessionKey: String) -> String {
        buffers[sessionKey] ?? ""
    }

    func mergeAXPrefix(_ axPrefix: String, sessionKey: String) {
        guard !axPrefix.isEmpty else { return }
        let existing = buffers[sessionKey] ?? ""
        if axPrefix.count >= existing.count || existing.isEmpty || axPrefix.hasPrefix(existing) {
            buffers[sessionKey] = String(axPrefix.suffix(1200))
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let pidKey = Self.pidKey(app.processIdentifier)

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == 48 { return }

        if keycode == 51 {
            applyBackspace(to: pidKey)
            if let sessionKey = activeSessionKey {
                applyBackspace(to: sessionKey)
            }
            notifyChange()
            return
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: 16, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }

        let chunk = String(utf16CodeUnits: chars, count: length)
        append(chunk, to: pidKey)
        if let sessionKey = activeSessionKey {
            append(chunk, to: sessionKey)
        }
        notifyChange()
    }

    private func applyBackspace(to sessionKey: String) {
        mutateBuffer(sessionKey: sessionKey) { buffer in
            guard !buffer.isEmpty else { return }
            buffer.removeLast()
        }
    }

    private func append(_ chunk: String, to sessionKey: String) {
        mutateBuffer(sessionKey: sessionKey) { buffer in
            buffer.append(contentsOf: chunk)
            if buffer.count > 1200 {
                buffer = String(buffer.suffix(1200))
            }
        }
    }

    static func pidKey(_ pid: pid_t) -> String {
        "pid:\(pid)"
    }

    func capturedPrefix(for target: SelectionTarget) -> String {
        let session = prefix(for: target.typingSessionKey)
        if !session.isEmpty { return session }
        let pid = target.focusedProcessID ?? 0
        return prefix(for: Self.pidKey(pid))
    }

    private func mutateBuffer(sessionKey: String, _ body: (inout String) -> Void) {
        var buffer = buffers[sessionKey] ?? ""
        body(&buffer)
        buffers[sessionKey] = buffer
    }

    private func notifyChange() {
        if Thread.isMainThread {
            onChange?()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        }
    }

    deinit {
        stop()
    }
}
