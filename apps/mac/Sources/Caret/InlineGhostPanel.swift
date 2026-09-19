import AppKit
import SwiftUI

@MainActor
final class InlineGhostPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 28),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        panel.contentView = container
    }

    func show(suffix: String, near anchor: CGRect) {
        label.stringValue = suffix
        label.sizeToFit()
        let width = min(max(label.intrinsicContentSize.width + 12, 40), 420)
        let height: CGFloat = 26
        var origin = CGPoint(x: anchor.maxX + 2, y: anchor.midY - height / 2)
        if let screen = AXHelpers.screen(containing: origin) {
            let visible = screen.visibleFrame
            if origin.x + width > visible.maxX - 8 {
                origin.x = anchor.minX - width - 2
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
