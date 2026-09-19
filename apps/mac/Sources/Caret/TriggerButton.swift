import AppKit
import SwiftUI

enum CaretPillMetrics {
    static let sparkleSize = NSSize(width: 40, height: 40)
    static let clusterHeight: CGFloat = 40
    static let pinIconCellWidth: CGFloat = 36
    static let clusterSpacing: CGFloat = 4
    static let stripCornerRadius: CGFloat = clusterHeight / 2
}

enum TriggerButtonPlacement {
    /// Tight rect the sparkle cluster sits beside (caret or selection).
    static func anchorRect(for target: SelectionTarget) -> CGRect {
        target.screenRect.standardized
    }

    /// Region that must stay uncovered by the cluster (usually just the caret line).
    static func avoidRect(for target: SelectionTarget, fieldFrame: CGRect?, anchor: CGRect) -> CGRect {
        guard target.kind == .input, let field = fieldFrame?.standardized else {
            return anchor.insetBy(dx: -8, dy: -8)
        }
        let insideField = field.insetBy(dx: -24, dy: -24).contains(anchor)
        if anchor.width <= 4, insideField {
            return field
        }
        return anchor.insetBy(dx: -8, dy: -8)
    }
}

enum TriggerButtonGeometry {
    /// Places the cluster beside `anchor`, preferring the right edge then the left.
    static func frame(adjacentTo anchor: CGRect, size: CGSize, visibleFrame: CGRect, gap: CGFloat = 6) -> CGRect {
        let padded = anchor.insetBy(dx: -8, dy: -8)
        let candidates = [
            CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2),
            CGPoint(x: anchor.minX - size.width - gap, y: anchor.midY - size.height / 2),
            CGPoint(x: anchor.maxX + gap, y: anchor.minY - size.height - gap),
            CGPoint(x: anchor.maxX + gap, y: anchor.maxY + gap),
        ]
        for origin in candidates {
            let clamped = CGPoint(
                x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
                y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
            )
            let frame = CGRect(origin: clamped, size: size)
            if !frame.intersects(padded) {
                return frame
            }
        }
        var fallback = CGRect(
            x: min(anchor.maxX + gap, visibleFrame.maxX - size.width),
            y: anchor.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        fallback.origin.x = min(max(fallback.origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        fallback.origin.y = min(max(fallback.origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return fallback
    }

    static func frame(avoiding textRect: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect? {
        guard !textRect.isNull, !textRect.isInfinite,
              size.width > 0, size.height > 0,
              size.width <= visibleFrame.width, size.height <= visibleFrame.height else { return nil }
        // Keep the entire cluster, including its shadow, out of the editable field.
        let protected = textRect.standardized.insetBy(dx: -8, dy: -8)
        let candidates = [
            CGPoint(x: protected.maxX, y: textRect.midY - size.height / 2),
            CGPoint(x: protected.minX - size.width, y: textRect.midY - size.height / 2),
            CGPoint(x: textRect.maxX - size.width, y: protected.minY - size.height),
            CGPoint(x: textRect.maxX - size.width, y: protected.maxY)
        ]
        for origin in candidates {
            let clamped = CGPoint(
                x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
                y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
            )
            let frame = CGRect(origin: clamped, size: size)
            if !frame.intersects(protected) { return frame }
        }
        // Clamping into a full-screen editor would cover text. Leave its shortcuts available.
        return nil
    }
}

struct PinnedActionChip: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let slot: Int
}

final class TriggerButtonController {
    var onClick: (() -> Void)?
    var onPinnedAction: ((PinnedActionChip) -> Void)?

    var buttonFrame: CGRect { panel.frame }

    private let panel = TriggerButtonPanel()
    private var lastRect: CGRect = .zero
    private var lastTarget: SelectionTarget?
    private var pinnedActions: [PinnedActionChip] = []
    private weak var chordState: ModifierChordState?

    init(chordState: ModifierChordState) {
        self.chordState = chordState
        panel.contentView = makeHostingView()
        panel.setContentSize(CaretPillMetrics.sparkleSize)
    }

    func setPinnedActions(_ actions: [PinnedActionChip]) {
        pinnedActions = actions
        panel.contentView = makeHostingView()
        panel.layoutIfNeeded()
        if let size = panel.contentView?.fittingSize, size.width > 1 {
            panel.setContentSize(NSSize(width: size.width, height: max(size.height, CaretPillMetrics.sparkleSize.height)))
        }
        if let lastTarget { update(target: lastTarget) }
    }

    private func makeHostingView() -> NSHostingView<TriggerClusterView> {
        let hosting = NSHostingView(
            rootView: TriggerClusterView(
                pinnedActions: pinnedActions,
                chordState: chordState!,
                onPinnedTap: { [weak self] chip in
                    self?.onPinnedAction?(chip)
                },
                onSparkleTap: { [weak self] in
                    self?.onClick?()
                }
            )
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        return hosting
    }

    func update(target: SelectionTarget?) {
        guard let target else {
            hide()
            return
        }

        lastTarget = target
        let size = panel.frame.size.width > 1 ? panel.frame.size : CaretPillMetrics.sparkleSize
        let fieldFrame: CGRect? = {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier == target.focusedProcessID,
                  let element = AXHelpers.focusedTextElement(in: app)
            else { return nil }
            return AXHelpers.frame(element)
        }()
        var anchor = TriggerButtonPlacement.anchorRect(for: target)
        if anchor.width <= 2, anchor.height <= 2 {
            anchor = CGRect(
                x: target.mouseLocation.x - 8,
                y: target.mouseLocation.y - 14,
                width: 16,
                height: 28
            )
        }
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = AXHelpers.screen(containing: point) else {
            panel.orderOut(nil)
            return
        }
        guard anchor.height > 1 else {
            panel.orderOut(nil)
            return
        }
        let avoid = TriggerButtonPlacement.avoidRect(for: target, fieldFrame: fieldFrame, anchor: anchor)
        let frame: CGRect
        if target.kind == .input || (target.kind == .selection && anchor.width > 4) {
            frame = TriggerButtonGeometry.frame(
                adjacentTo: anchor,
                size: size,
                visibleFrame: screen.visibleFrame
            )
        } else if let legacy = TriggerButtonGeometry.frame(
            avoiding: avoid,
            size: size,
            visibleFrame: screen.visibleFrame
        ) {
            frame = legacy
        } else {
            panel.orderOut(nil)
            lastRect = .zero
            return
        }
        _ = avoid

        if panel.isVisible, frame == lastRect { return }

        lastRect = frame
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        lastTarget = nil
        lastRect = .zero
        panel.orderOut(nil)
    }
}

final class TriggerButtonPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: CaretPillMetrics.sparkleSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct TriggerClusterView: View {
    let pinnedActions: [PinnedActionChip]
    @ObservedObject var chordState: ModifierChordState
    let onPinnedTap: (PinnedActionChip) -> Void
    let onSparkleTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CaretPillMetrics.clusterSpacing) {
            TriggerButtonView(onClick: onSparkleTap)
            if !pinnedActions.isEmpty {
                PinnedGlassStrip(actions: pinnedActions, chordState: chordState, onTap: onPinnedTap)
            }
        }
        .frame(height: CaretPillMetrics.clusterHeight)
    }
}

private struct PinnedGlassStrip: View {
    let actions: [PinnedActionChip]
    @ObservedObject var chordState: ModifierChordState
    let onTap: (PinnedActionChip) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, chip in
                if index > 0 {
                    Rectangle()
                        .fill(.primary.opacity(0.12))
                        .frame(width: 1, height: 14)
                }
                PinnedStripCell(
                    chip: chip,
                    showShortcut: chordState.commandOptionHeld,
                    isFirst: index == 0,
                    isLast: index == actions.count - 1
                ) {
                    onTap(chip)
                }
            }
        }
        .frame(height: CaretPillMetrics.clusterHeight)
        .caretGlassCapsule()
    }
}

private struct PinnedStripCell: View {
    let chip: PinnedActionChip
    let showShortcut: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var hoverShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? CaretPillMetrics.stripCornerRadius : 0,
            bottomLeadingRadius: isFirst ? CaretPillMetrics.stripCornerRadius : 0,
            bottomTrailingRadius: isLast ? CaretPillMetrics.stripCornerRadius : 0,
            topTrailingRadius: isLast ? CaretPillMetrics.stripCornerRadius : 0,
            style: .continuous
        )
    }

    var body: some View {
        Button(action: action) {
            Group {
                if showShortcut {
                    Text(PinnedShortcutFormatting.menuLabel(slot: chip.slot))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                } else {
                    Image(systemName: chip.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(.primary)
            // Keyboard hints must appear immediately when the modifier chord changes.
            .frame(width: showShortcut ? 44 : CaretPillMetrics.pinIconCellWidth)
            .padding(.horizontal, showShortcut ? 6 : 4)
            .frame(maxHeight: .infinity)
                .background {
                    if isHovered {
                        hoverShape.fill(Color.primary.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(chip.title)
        .accessibilityHint("Opens actions for \(chip.title)")
        .help("\(chip.title) (\(PinnedShortcutFormatting.menuLabel(slot: chip.slot)))")
    }
}

private extension View {
    @ViewBuilder
    func caretGlassCapsule() -> some View {
        // `#available` is runtime-only. Xcode 16 still type-checks glassEffect
        // and fails. The modifier exists on Swift 6.2+ / Xcode 26 SDKs.
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            caretMaterialCapsule()
        }
#else
        caretMaterialCapsule()
#endif
    }

    func caretMaterialCapsule() -> some View {
        background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

struct TriggerButtonView: View {
    let onClick: () -> Void
    @State private var isHovered = false

    private let blue = Color(red: 0.26, green: 0.52, blue: 0.98)

    var body: some View {
        Button(action: onClick) {
            Image(systemName: "sparkle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(blue.opacity(isHovered ? 1 : 0.96)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open Caret actions")
        .help("Open Caret actions")
        .frame(width: 40, height: 40)
    }
}
