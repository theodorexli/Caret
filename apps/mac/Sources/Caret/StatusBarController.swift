import AppKit
import ApplicationServices

final class StatusBarController: NSObject, NSMenuDelegate {
    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onFixAccessibility: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var accessibilityItem: NSMenuItem?

    func install() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Caret")
            image?.isTemplate = true
            button.image = image
            button.title = " Caret"
            button.toolTip = "Caret"
        }

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: "Open Caret (⌘⌥)", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let axItem = NSMenuItem(title: "Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        accessibilityItem = axItem

        let repairItem = NSMenuItem(title: "Reconnect Accessibility…", action: #selector(fixAccessibility), keyEquivalent: "")
        repairItem.target = self
        menu.addItem(repairItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Caret", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let trusted = AXHelpers.isTrusted()
        accessibilityItem?.title = trusted ? "Accessibility: connected" : "Accessibility: not connected to this build"
        if let button = statusItem.button {
            let name = trusted ? "sparkle" : "exclamationmark.triangle"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "Caret")
            image?.isTemplate = true
            button.image = image
        }
    }

    @objc private func openPanel() {
        onOpen?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func openAccessibility() {
        AXHelpers.openAccessibilitySettings()
    }

    @objc private func fixAccessibility() {
        onFixAccessibility?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
