import AppKit
import Foundation

@MainActor
final class TabCompletionsController {
    enum Presentation: Equatable {
        case inlineSelection(NSRange)
        case ghostOverlay
    }

    struct Offer: Equatable {
        let suffix: String
        let presentation: Presentation
        let insertedRange: NSRange
        let processID: pid_t
        let anchor: CGRect
    }

    var configuration: () -> (instructions: String, excludedApps: [String]) = { ("", []) }

    private let tabMonitor = TabInterceptMonitor()
    private let ghostPanel = InlineGhostPanel()
    private var offer: Offer?
    private var fetchTask: Task<Void, Never>?
    private var lastPresentedSuffix: String?

    private let debounceNs: UInt64 = 550_000_000

    func update(target: SelectionTarget?) {
        guard AXHelpers.isTrusted() else {
            clearOffer()
            return
        }
        guard let target, target.kind == .input else {
            clearOffer()
            return
        }

        let config = configuration()
        if isExcluded(appName: target.sourceApp, excluded: config.excludedApps) {
            clearOffer()
            return
        }

        let captured = TypingPrefixCapture.shared.capturedPrefix(for: target)
        let prefix = target.effectivePrefix(captured: captured)
        guard prefix.count >= TabCompletions.minimumTypedCharacters else {
            clearOffer()
            return
        }

        let instructions = config.instructions
        let patternSuffix = TabCompletionsPatterns.completionSuffix(
            prefix: prefix,
            instructions: instructions
        )
        if !patternSuffix.isEmpty {
            fetchTask?.cancel()
            fetchTask = nil
            presentInlineOffer(
                suffix: patternSuffix,
                processID: target.focusedProcessID ?? 0,
                anchor: target.screenRect
            )
            return
        }

        if offer != nil {
            return
        }

        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await fetchCompletion(
                prefix: prefix,
                instructions: instructions,
                processID: target.focusedProcessID ?? 0,
                anchor: target.screenRect
            )
        }
    }

    func clearOffer() {
        revertActiveOfferIfNeeded()
        fetchTask?.cancel()
        fetchTask = nil
        offer = nil
        lastPresentedSuffix = nil
        ghostPanel.hide()
        tabMonitor.setActive(false, onTab: nil)
    }

    private func fetchCompletion(
        prefix: String,
        instructions: String,
        processID: pid_t,
        anchor: CGRect
    ) async {
        guard prefix.count >= TabCompletions.minimumTypedCharacters else {
            clearOffer()
            return
        }
        do {
            let suffix = try await CaretCLI.autoExpand(prefix: prefix, instructions: instructions)
            guard !Task.isCancelled, !suffix.isEmpty else {
                clearOffer()
                return
            }
            presentInlineOffer(suffix: suffix, processID: processID, anchor: anchor)
        } catch CaretCLI.Error.missingProjectRoot {
            clearOffer()
        } catch {
            NSLog("[Caret] Tab completion failed: %@", String(describing: error))
            clearOffer()
        }
    }

    private func presentInlineOffer(suffix: String, processID: pid_t, anchor: CGRect) {
        guard let app = NSRunningApplication(processIdentifier: processID),
              app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            clearOffer()
            return
        }

        let element = AXHelpers.focusedTextElement(in: app)
        let caretAnchor = element.flatMap { AXHelpers.caretBounds($0) } ?? anchor

        if offer?.suffix == suffix, lastPresentedSuffix == suffix {
            tabMonitor.setActive(true) { [weak self] in
                self?.acceptCurrentOffer() ?? false
            }
            return
        }

        revertActiveOfferIfNeeded()

        if let element,
           let insertedRange = AXHelpers.insertInlineSuggestion(element, suffix: suffix)
        {
            ghostPanel.hide()
            offer = Offer(
                suffix: suffix,
                presentation: .inlineSelection(insertedRange),
                insertedRange: insertedRange,
                processID: processID,
                anchor: caretAnchor
            )
            lastPresentedSuffix = suffix
            tabMonitor.setActive(true) { [weak self] in
                self?.acceptCurrentOffer() ?? false
            }
            return
        }

        ghostPanel.show(suffix: suffix, near: caretAnchor)
        offer = Offer(
            suffix: suffix,
            presentation: .ghostOverlay,
            insertedRange: NSRange(location: NSNotFound, length: 0),
            processID: processID,
            anchor: caretAnchor
        )
        lastPresentedSuffix = suffix
        tabMonitor.setActive(true) { [weak self] in
            self?.acceptCurrentOffer() ?? false
        }
    }

    private func acceptCurrentOffer() -> Bool {
        guard let current = offer else { return false }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == current.processID
        else {
            clearOffer()
            return false
        }

        switch current.presentation {
        case .ghostOverlay:
            guard TextTyping.postUnicodeText(current.suffix) else {
                clearOffer()
                return false
            }
            ghostPanel.hide()
            offer = nil
            lastPresentedSuffix = nil
            tabMonitor.setActive(false, onTab: nil)
            return true

        case .inlineSelection:
            guard let element = AXHelpers.focusedTextElement(in: app) else {
                clearOffer()
                return false
            }

            guard let selected = AXHelpers.selectedTextRange(element),
                  selected.location == current.insertedRange.location,
                  selected.length == current.insertedRange.length,
                  let value = AXHelpers.fieldValue(element),
                  value.substring(with: selected) == current.suffix
            else {
                offer = nil
                lastPresentedSuffix = nil
                tabMonitor.setActive(false, onTab: nil)
                return false
            }

            let caret = NSRange(
                location: current.insertedRange.location + current.insertedRange.length,
                length: 0
            )
            _ = AXHelpers.setSelectedTextRange(element, range: caret)
            offer = nil
            lastPresentedSuffix = nil
            tabMonitor.setActive(false, onTab: nil)
            return true
        }
    }

    private func revertActiveOfferIfNeeded() {
        guard let current = offer else { return }

        switch current.presentation {
        case .ghostOverlay:
            ghostPanel.hide()
            offer = nil
            return

        case .inlineSelection:
            guard let app = NSRunningApplication(processIdentifier: current.processID),
                  let element = AXHelpers.focusedTextElement(in: app)
            else {
                offer = nil
                return
            }
            if let value = AXHelpers.fieldValue(element) {
                let ns = value as NSString
                if NSMaxRange(current.insertedRange) <= ns.length {
                    let inserted = ns.substring(with: current.insertedRange)
                    if inserted == current.suffix {
                        _ = AXHelpers.removeRange(element, range: current.insertedRange)
                    }
                }
            }
            offer = nil
        }
    }

    private func isExcluded(appName: String?, excluded: [String]) -> Bool {
        guard let appName, !appName.isEmpty else { return false }
        let lowered = appName.lowercased()
        return excluded.contains { entry in
            let needle = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return false }
            return lowered.contains(needle) || needle.contains(lowered)
        }
    }
}

private extension String {
    func substring(with range: NSRange) -> String {
        (self as NSString).substring(with: range)
    }
}
