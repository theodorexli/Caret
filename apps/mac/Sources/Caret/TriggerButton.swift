import AppKit
import SwiftUI

enum CaretPillMetrics {
    static let sparkleSize = NSSize(width: 40, height: 40)
    static let clusterHeight: CGFloat = 40
    static let pinIconCellWidth: CGFloat = 36
    static let clusterSpacing: CGFloat = 4
    static let stripCornerRadius: CGFloat = clusterHeight / 2
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
        if panel.isVisible, lastRect != .zero {
            var frame = lastRect
            frame.size = panel.frame.size
            lastRect = frame
            panel.setFrame(frame, display: true)
        }
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

        let size = panel.frame.size.width > 1 ? panel.frame.size : CaretPillMetrics.sparkleSize
        let point = target.anchor
        var origin = CGPoint(x: point.x + 10, y: point.y - size.height / 2)
        var frame = CGRect(origin: origin, size: size)

        if let screen = AXHelpers.screen(containing: point) {
            if frame.maxX > screen.visibleFrame.maxX {
                origin.x = point.x - size.width - 10
            }
            frame = AXHelpers.clamp(CGRect(origin: origin, size: size), to: screen.visibleFrame)
        }

        if panel.isVisible, hypot(frame.midX - lastRect.midX, frame.midY - lastRect.midY) < 3 {
            return
        }

        lastRect = frame
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
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
