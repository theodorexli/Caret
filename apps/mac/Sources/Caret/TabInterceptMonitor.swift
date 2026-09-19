import AppKit
import ApplicationServices

final class TabInterceptMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (() -> Bool)?

    func setActive(_ active: Bool, onTab: (() -> Bool)?) {
        if active, let onTab {
            handler = onTab
            startIfNeeded()
        } else {
            handler = nil
            stop()
        }
    }

    private func startIfNeeded() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TabInterceptMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // The window server disables a tap whose callback ran long.
                // The accept path below reads the field over AX on the main
                // thread, which a large document can make slow, so this does
                // happen. Without re-enabling, Tab silently stops working in
                // every app until relaunch, which reads as "Tab works in some
                // apps and not others".
                if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                NSLog("[Caret] Tab event tap was disabled by the system; re-enabled")
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            guard event.getIntegerValueField(.keyboardEventKeycode) == 48 else {
                return Unmanaged.passUnretained(event)
            }
            var consumed = false
            if Thread.isMainThread {
                consumed = monitor.handler?() ?? false
            } else {
                DispatchQueue.main.sync {
                    consumed = monitor.handler?() ?? false
                }
            }
            if consumed {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[Caret] Tab event tap unavailable (Accessibility required)")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}
