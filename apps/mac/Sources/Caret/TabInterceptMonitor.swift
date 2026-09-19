import AppKit
import ApplicationServices

final class TabInterceptMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (() -> Bool)?
    private var dismissHandler: (() -> Void)?

    func setActive(_ active: Bool, onTab: (() -> Bool)?, onDismiss: (() -> Void)? = nil) {
        if active, let onTab {
            handler = onTab
            dismissHandler = onDismiss
            startIfNeeded()
        } else {
            handler = nil
            dismissHandler = nil
            stop()
        }
    }

    private func startIfNeeded() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TabInterceptMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            // Any other keystroke invalidates the preview before the host edits.
            if key != 48 || !event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty {
                monitor.dismissHandler?()
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                return Unmanaged.passUnretained(event)
            }
            // Shift-Tab and app shortcuts retain their normal navigation behavior.
            guard event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty,
                  event.getIntegerValueField(.keyboardEventKeycode) == 48 else {
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
