import AppKit
import ApplicationServices

final class HotKeyManager {
    var onHotKey: ((CGPoint) -> Void)?
    var onPinnedHotKey: ((Int) -> Void)?
    var onCommandOptionHeld: ((Bool) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trustTimer: Timer?
    private var chordArmed = false
    private var sawOtherKey = false

    func register() {
        installChordMonitors()

        if !AXHelpers.isTrusted() {
            trustTimer?.invalidate()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard AXHelpers.isTrusted() else { return }
                timer.invalidate()
                self?.trustTimer = nil
                self?.installChordMonitors()
            }
        }
    }

    func unregister() {
        trustTimer?.invalidate()
        trustTimer = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        unregister()
    }

    private func fireToggle() {
        onHotKey?(NSEvent.mouseLocation)
    }

    private func installChordMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if Self.shouldDeliverToTextInput(event) {
                return event
            }
            self?.handle(event)
            return event
        }
    }

    private static func shouldDeliverToTextInput(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        if let view = responder as? NSView, view.className.contains("FieldEditor") {
            return true
        }
        return false
    }

    private func handle(_ event: NSEvent) {
        reportCommandOptionHeld(from: event)

        if event.type == .keyDown {
            if handlePinnedShortcut(event) {
                return
            }
            if chordArmed {
                sawOtherKey = true
            }
            return
        }

        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if flags == [.command, .option] {
            chordArmed = true
            sawOtherKey = false
            return
        }

        if chordArmed {
            chordArmed = false
            if !sawOtherKey {
                fireToggle()
            }
            sawOtherKey = false
        }
    }

    private func handlePinnedShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard flags == [.command, .option], let slot = slot(forKeyCode: event.keyCode) else {
            return false
        }
        chordArmed = false
        sawOtherKey = true
        onPinnedHotKey?(slot)
        return true
    }

    private func reportCommandOptionHeld(from event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        onCommandOptionHeld?(flags == [.command, .option])
    }

    private func slot(forKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        default: return nil
        }
    }
}
