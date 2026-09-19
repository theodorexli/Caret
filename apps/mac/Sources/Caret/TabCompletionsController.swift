import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TabCompletionsController {
    struct Snapshot: Equatable {
        let processID: pid_t
        let element: AXUIElement
        let value: String
        let selection: NSRange
        let anchor: CGRect

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.processID == rhs.processID && CFEqual(lhs.element, rhs.element)
                && lhs.value == rhs.value && lhs.selection == rhs.selection && lhs.anchor == rhs.anchor
        }

        static func capture() -> Snapshot? {
            guard AXHelpers.isTrusted(),
                  let app = NSWorkspace.shared.frontmostApplication,
                  let element = AXHelpers.focusedElement(in: app),
                  AXHelpers.stringValue(element, kAXSubroleAttribute as CFString) != kAXSecureTextFieldSubrole as String,
                  let value = AXHelpers.stringValue(element, kAXValueAttribute as CFString),
                  let selection = AXHelpers.selectedTextRange(element),
                  selection.length == 0, selection.location >= 0,
                  selection.location <= (value as NSString).length,
                  let anchor = AXHelpers.caretBounds(element)
            else { return nil }
            return Snapshot(processID: app.processIdentifier, element: element,
                            value: value, selection: selection, anchor: anchor)
        }

        var prefix: String {
            (value as NSString).substring(to: selection.location)
        }
    }

    // The only write capability is invoked from acceptCurrentOffer. Preview and
    // dismissal operate on a separate panel and never edit the host document.
    struct Environment {
        var capture: () -> Snapshot?
        var show: (String, CGRect) -> Bool
        var hide: () -> Void
        var arm: ((() -> Bool)?, (() -> Void)?) -> Void
        var insert: (String) -> Bool
        var complete: (String, String) async throws -> String
        var debounceNs: UInt64 = 550_000_000
    }

    private struct Offer {
        let suffix: String
        let snapshot: Snapshot
    }

    var configuration: () -> (instructions: String, excludedApps: [String]) = { ("", []) }
    private let environment: Environment
    private var offer: Offer?
    private var requestID = UUID()
    private var requestedSnapshot: Snapshot?
    private var suppressedSnapshot: Snapshot?
    private var fetchTask: Task<Void, Never>?

    init(environment: Environment? = nil) {
        if let environment {
            self.environment = environment
        } else {
            let panel = InlineGhostPanel()
            let monitor = TabInterceptMonitor()
            self.environment = Environment(
                capture: { Snapshot.capture() },
                show: { panel.show(suffix: $0, near: $1) },
                hide: { panel.hide() },
                arm: { accept, dismiss in
                    monitor.setActive(accept != nil, onTab: accept, onDismiss: dismiss)
                },
                insert: { TextTyping.postUnicodeText($0) },
                complete: { try await CaretCLI.autoExpand(prefix: $0, instructions: $1) }
            )
        }
    }

    func update(target: SelectionTarget?) {
        guard let target, target.kind == .input,
              let snapshot = environment.capture(),
              snapshot.processID == target.focusedProcessID
        else {
            clearOffer()
            return
        }
        let config = configuration()
        guard !isExcluded(appName: target.sourceApp, excluded: config.excludedApps) else {
            clearOffer()
            return
        }
        // Posting accepted text is asynchronous. Do not re-offer the same suffix
        // while the host has yet to process the accepted keystroke.
        guard suppressedSnapshot != snapshot else { return }
        suppressedSnapshot = nil
        if requestedSnapshot == snapshot { return }
        clearOffer()
        let prefix = snapshot.prefix
        guard TabCompletionsPatterns.meetsMinimumTyping(prefix) else { return }
        requestedSnapshot = snapshot
        let id = requestID
        if let pattern = TabCompletionsPatterns.completionMatch(
            fullPrefix: prefix, instructions: config.instructions
        ) {
            present(suffix: pattern.suffix, snapshot: snapshot, requestID: id)
            return
        }
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: environment.debounceNs)
                guard !Task.isCancelled, requestID == id else { return }
                let suffix = try await environment.complete(prefix, config.instructions)
                guard !Task.isCancelled, requestID == id else { return }
                present(suffix: suffix, snapshot: snapshot, requestID: id)
            } catch {
                // A cancelled request must not dismiss its successor's preview.
                guard !Task.isCancelled, requestID == id else { return }
                clearOffer()
                NSLog("[Caret] Tab completion failed: %@", CaretCLI.userFacingMessage(for: error))
            }
        }
    }

    func clearOffer() {
        requestID = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        requestedSnapshot = nil
        offer = nil
        environment.hide()
        environment.arm(nil, nil)
    }

    private func present(suffix: String, snapshot: Snapshot, requestID id: UUID) {
        guard id == requestID, !suffix.isEmpty,
              environment.capture() == snapshot else { return }
        guard environment.show(suffix, snapshot.anchor) else { return }
        offer = Offer(suffix: suffix, snapshot: snapshot)
        environment.arm({ [weak self] in self?.acceptCurrentOffer() ?? false }, { [weak self] in
            guard let self else { return }
            suppressedSnapshot = offer?.snapshot
            clearOffer()
        })
    }

    private func acceptCurrentOffer() -> Bool {
        guard let current = offer, environment.capture() == current.snapshot else {
            clearOffer()
            return false
        }
        // Retire before posting, so a second Tab cannot accept the same offer.
        suppressedSnapshot = current.snapshot
        clearOffer()
        return environment.insert(current.suffix)
    }

    private func isExcluded(appName: String?, excluded: [String]) -> Bool {
        guard let appName, !appName.isEmpty else { return false }
        let lowered = appName.lowercased()
        return excluded.contains { entry in
            let needle = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !needle.isEmpty && (lowered.contains(needle) || needle.contains(lowered))
        }
    }
}
