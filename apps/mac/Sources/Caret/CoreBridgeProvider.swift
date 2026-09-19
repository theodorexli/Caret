import Foundation
import CaretCore
import os

/// An action Caret is offering, and what happened when it ran.
///
/// `status` is taken from the core's `WorkflowExecution`, never synthesized:
/// "request sent" and "succeeded" are different facts and the UI must not
/// conflate them.
struct CaretActionOffer: Identifiable, Equatable {
    enum State: Equatable {
        case offered
        case running
        /// The run finished. `scope` says what actually happened, because
        /// "completed" from the core means the adapter finished its own job,
        /// not that the user's goal in the world was met.
        case succeeded(summary: String, evidence: [String], scope: CompletionScope)
        case failed(summary: String)
        /// The user or the adapter stopped it. Not a failure.
        case cancelled(summary: String)
        /// The core has no executor for this workflow, or required inputs are
        /// missing. Not a failure of a run -- nothing ran.
        case unavailable(reason: String)
    }

    var id: String { proposalID }
    var proposalID: String
    var revision: Int
    var target: TargetIdentity
    var workflowID: String
    var title: String
    var effect: String
    var evidence: [String]
    var missingInputs: [String]
    var executionMethod: String
    var sampleOnly: Bool
    var state: State = .offered

    /// How much of the user's goal a successful run actually accomplished.
    ///
    /// `book-calendar-link` returns status "completed" with
    /// execution_method "draft_only", meaning it produced draft text and
    /// explicitly did not send a message or create a calendar event. Rendering
    /// that as "Done" would tell the user a meeting was scheduled. The two are
    /// kept apart here so the label can differ.
    enum CompletionScope: Equatable {
        case externalEffect
        case draftOnly
        case localDemo

        var label: String {
            switch self {
            case .externalEffect: return "Done"
            case .draftOnly: return "Draft ready"
            case .localDemo: return "Demo holds created"
            }
        }
    }

    /// Execution methods whose run produces something to review rather than an
    /// effect in the world. Read off the adapter contract, not guessed.
    static let draftOnlyExecutionMethods: Set<String> = ["draft_only"]

    /// Execution methods that name the absence of an executor rather than one.
    ///
    /// Read off the live core, not guessed: `workflows.list` on the real
    /// bridge returns `"unwired"` for book-flight and revise, and
    /// `"local-sample-planner"` with `sample_only: true` for
    /// book-calendar-link. A non-empty check alone would have called "unwired"
    /// runnable and offered the user a workflow that cannot execute.
    static let placeholderExecutionMethods: Set<String> = ["unwired", "none", "unavailable"]

    /// A catalog entry is something the core can describe but not run. It is
    /// shown as unavailable rather than offered, because presenting it as a
    /// choice would promise an execution that cannot happen.
    ///
    /// A core-minted offer already implies availability: the engine filters
    /// the registry to available adapters, validates the judge's answer
    /// against exactly those ids, then re-checks the selected adapter's
    /// availability before building the offer. That is availability AT MINT
    /// TIME ONLY. It is not a promise the adapter is still runnable when the
    /// user presses the key, which is why an acceptance failure stays visible
    /// rather than being treated as impossible.
    var isExecutable: Bool {
        isExecutable(demoMeetingEnabled: CoreLaunchSettings.demoMeetingEnabled)
    }

    var isLocalMeetingDemo: Bool {
        sampleOnly && workflowID == "book-calendar-link" && executionMethod == "local-sample-planner"
    }

    func isExecutable(demoMeetingEnabled: Bool) -> Bool {
        guard missingInputs.isEmpty else { return false }
        guard !sampleOnly || (demoMeetingEnabled && isLocalMeetingDemo) else { return false }
        let method = executionMethod.trimmingCharacters(in: .whitespaces).lowercased()
        return !method.isEmpty && !Self.placeholderExecutionMethods.contains(method)
    }

    var unavailabilityText: String? {
        unavailabilityText(demoMeetingEnabled: CoreLaunchSettings.demoMeetingEnabled)
    }

    /// Explicit-input form, mirroring `isExecutable(demoMeetingEnabled:)`, so
    /// the rule can be tested without depending on whatever dev.json the
    /// machine happens to have. The ambient property above reads the real
    /// flag at runtime.
    func unavailabilityText(demoMeetingEnabled: Bool) -> String? {
        let method = executionMethod.trimmingCharacters(in: .whitespaces).lowercased()
        if sampleOnly && !(isLocalMeetingDemo && demoMeetingEnabled) {
            return "Sample only. \(displayTitle) has no live executor yet."
        }
        if method.isEmpty || Self.placeholderExecutionMethods.contains(method) {
            return "\(displayTitle) is described but not wired to an executor yet."
        }
        if !missingInputs.isEmpty {
            return "Needs \(missingInputs.joined(separator: ", ")) before it can run."
        }
        return nil
    }

    var displayTitle: String { title.isEmpty ? workflowID : title }

    /// Evidence rows to show for a finished run.
    ///
    /// A draft-only run shows all of it, uncapped. The adapter puts its
    /// no-effect disclosure ("No message was sent, and no calendar event was
    /// created, held or modified") in evidence, and that sentence is the whole
    /// reason the user does not mistake a draft for a booking. Dropping it to
    /// keep a row count tidy would undo the disclosure.
    static func visibleEvidence(_ evidence: [String], scope: CompletionScope) -> [String] {
        scope == .externalEffect ? Array(evidence.prefix(4)) : evidence
    }

    var completionScope: CompletionScope {
        if isLocalMeetingDemo { return .localDemo }
        return Self.draftOnlyExecutionMethods.contains(executionMethod.trimmingCharacters(in: .whitespaces).lowercased())
            ? .draftOnly
            : .externalEffect
    }
}

/// The app's single connection to the Python core.
///
/// One `CoreBridgeClient` and one `FocusedTargetCapture` serve both inline
/// completions and actions. They must be the same instances: the capture mints
/// the element and window tokens that `InsertionGuard` later compares, so a
/// second capture would mint different tokens and every acceptance would be
/// rejected as a moved target.
@MainActor
final class CoreBridgeProvider: InlineCompletionProviding {
    var onOffer: ((InlineOffer, Int) -> Void)?
    var onInvalidated: ((String, InlineCancelReason) -> Void)?
    var onUnavailable: ((InlineDisabledReason) -> Void)?

    /// Action offers and their state changes, for the picker to render.
    var onActionOffer: ((CaretActionOffer) -> Void)?
    var onActionStateChange: ((String, CaretActionOffer.State) -> Void)?
    /// The set of offers changed, so the UI list and the key tap's choice
    /// count both need recomputing.
    var onActionsChanged: (() -> Void)?

    let capture: FocusedTargetCapture
    private var client: CoreBridgeClient?
    private let log = Logger(subsystem: "com.caret.app", category: "core-provider")

    /// Generation of the request each proposal belongs to, so a late answer
    /// can be fenced by the offer store.
    private var generationForRevision: [Int: Int] = [:]
    private var actionOffers: [String: CaretActionOffer] = [:]
    /// Proposals whose acceptance is in flight. Synchronous claim: a second
    /// Cmd-1 or a repeated click cannot start the same workflow twice.
    private var executing: Set<String> = []

    private(set) var unavailableText: String?

    init(capture: FocusedTargetCapture) {
        self.capture = capture
    }

    func start() throws {
        switch CoreLaunchSettings.resolve() {
        case .failure(let unavailable):
            unavailableText = unavailable.statusText
            onUnavailable?(unavailable.reason)
            throw unavailable
        case .success(let configuration):
            let client = CoreBridgeClient(configuration: configuration)
            // Installed before start() so no event between launch and hello
            // is lost.
            client.onEvent { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            try client.start()
            self.client = client
            Task { @MainActor in
                do {
                    _ = try await client.hello()
                    self.unavailableText = nil
                } catch {
                    self.unavailableText = "The completion backend did not answer its handshake."
                    self.onUnavailable?(.providerError)
                }
            }
        }
    }

    func shutdown() async {
        await client?.shutdown()
        client = nil
    }

    // MARK: - Requests

    func requestCompletion(_ request: InlineCompletionRequest) async throws {
        guard let client else { throw InlineProviderError.notRunning }
        generationForRevision[request.revision] = request.generation
        let frame = ContextFrame(
            snapshot: request.snapshot,
            permissions: capture.permissions(),
            clipboard: capture.clipboardContext(now: Date()),
            sources: capture.sourceRecords()
        )
        _ = try await client.updateContext(frame)
    }

    func accept(proposalID: String, revision: Int, target: InlineTarget) async throws -> InlineAcceptedEdit {
        guard let client else { throw InlineProviderError.notRunning }
        let result = try await client.accept(
            proposalID: proposalID,
            revision: revision,
            target: target.identity
        )
        guard case .inline(let edit) = result else {
            throw InlineProviderError.wrongResultKind
        }
        return InlineAcceptedEdit(
            proposalID: edit.proposalID,
            target: InlineTarget(edit.target),
            replaceStart: edit.replaceStart,
            replaceEnd: edit.replaceEnd,
            replacement: edit.replacement,
            originalDigest: edit.originalDigest
        )
    }

    func dismiss(proposalID: String) async {
        actionOffers[proposalID] = nil
        executing.remove(proposalID)
        _ = try? await client?.dismiss(proposalID: proposalID)
    }

    // MARK: - Actions

    var visibleExecutableActions: [CaretActionOffer] {
        actionOffers.values.filter { $0.isExecutable }.sorted { $0.proposalID < $1.proposalID }
    }

    func actionOffer(id: String) -> CaretActionOffer? { actionOffers[id] }

    /// The user left the field or focus changed. Offers were prepared against
    /// that context, so they stop being valid whether or not the core has
    /// noticed yet. A run already in flight is left alone: it owns its own
    /// outcome and will report it.
    func invalidateContextualOffers() {
        let removable = actionOffers.keys.filter { !executing.contains($0) }
        guard !removable.isEmpty else { return }
        log.info("dropping \(removable.count, privacy: .public) action offer(s): context invalidated")
        for id in removable { actionOffers[id] = nil }
        onActionsChanged?()
    }

    /// Runs an offered action exactly once.
    ///
    /// The claim is synchronous and taken before any await, so two keystrokes
    /// arriving in the same run loop turn cannot both pass it.
    func runAction(proposalID: String) {
        guard var offer = actionOffers[proposalID] else { return }
        guard offer.isExecutable else {
            let reason = offer.unavailabilityText ?? "This action has no executor."
            offer.state = .unavailable(reason: reason)
            actionOffers[proposalID] = offer
            onActionStateChange?(proposalID, offer.state)
            return
        }
        guard !executing.contains(proposalID) else { return }
        executing.insert(proposalID)

        // Running is shown immediately, before the request leaves, so the user
        // never sees a dead panel while a workflow is in flight.
        offer.state = .running
        actionOffers[proposalID] = offer
        onActionStateChange?(proposalID, .running)

        guard let client else {
            finish(proposalID, .unavailable(reason: "The backend is not running."))
            return
        }

        // Blocker 1: the offer's target was captured when the offer was
        // minted, which may be many seconds and several keystrokes ago. An
        // action can rewrite the user's text, so sending a saved target
        // unchecked risks acting on a field they have left. Revalidate against
        // the live field first and refuse on any mismatch.
        guard let live = capture.liveTarget() else {
            finish(proposalID, .unavailable(reason: "Caret can no longer read the field this action was prepared for."))
            return
        }
        if let mismatch = Self.staleness(offerTarget: offer.target, live: live) {
            finish(proposalID, .unavailable(reason: mismatch))
            return
        }

        Task { @MainActor in
            do {
                let result = try await client.accept(
                    proposalID: proposalID,
                    revision: offer.revision,
                    target: offer.target
                )
                switch result {
                case .action(let execution):
                    self.finish(proposalID, Self.actionState(for: execution, scope: offer.completionScope))
                case .inline:
                    self.finish(proposalID, .failed(summary: "The core answered with a text edit, not a run."))
                }
            } catch let error as BridgeError {
                self.finish(proposalID, Self.actionState(for: error))
            } catch {
                self.finish(proposalID, .failed(summary: "The run could not be completed."))
            }
        }
    }

    /// Why a saved action target no longer matches the live field, or nil
    /// when it still does.
    ///
    /// Identity is compared without the content token first, so "you moved to
    /// a different field" and "you edited this field" stay distinguishable:
    /// they are different things to tell the user.
    nonisolated static func staleness(
        offerTarget: TargetIdentity,
        live: InsertionGuard.LiveField
    ) -> String? {
        if live.secure { return "That field is secure, so Caret will not act on it." }

        var expected = offerTarget
        var actual = live.target
        expected.elementRevision = ""
        actual.elementRevision = ""
        guard expected == actual else {
            return "The focus moved to a different field, so nothing ran."
        }
        guard offerTarget.elementRevision == live.target.elementRevision else {
            return "The text changed after this was prepared, so nothing ran."
        }
        return nil
    }

    /// The core's ExecutionResult permits exactly four statuses:
    /// completed, needs_input, failed and cancelled. Anything else is a
    /// contract change and is surfaced rather than guessed at.
    ///
    /// "completed" is deliberately not called success on its own. It means the
    /// adapter finished, and `scope` carries whether that produced an effect
    /// in the world or only something to review.
    nonisolated static func actionState(
        for execution: WorkflowExecution,
        scope: CaretActionOffer.CompletionScope
    ) -> CaretActionOffer.State {
        let summary = execution.summary.isEmpty ? "The workflow returned no summary." : execution.summary
        switch execution.status.lowercased() {
        case "completed":
            return .succeeded(summary: summary, evidence: execution.evidence, scope: scope)
        case "needs_input":
            return .unavailable(reason: summary)
        case "cancelled", "canceled":
            return .cancelled(summary: summary)
        case "failed":
            return .failed(summary: summary)
        default:
            return .failed(summary: "The core reported an unrecognized status \"\(execution.status)\": \(summary)")
        }
    }

    /// The core's error codes mean materially different things to a user, so
    /// they are not collapsed into one failure string.
    ///
    /// `acceptance_rejected` means the core refused the acceptance as stale,
    /// duplicate or expired and *nothing ran*. `workflow_error` and
    /// `provider_error` mean it did run and failed. `internal_error` is the
    /// core's catch-all for an unhandled exception: it displays like a
    /// failure, but it means the core hit something unexpected rather than a
    /// provider misbehaving, so it is worth saying so and worth its own log
    /// line when someone goes looking.
    nonisolated static func actionState(for error: BridgeError) -> CaretActionOffer.State {
        guard case .core(let code, let message) = error else {
            return .failed(summary: "The backend stopped responding.")
        }
        switch code {
        case "acceptance_rejected":
            return .unavailable(reason: "That suggestion is no longer current, so nothing ran.")
        case "internal_error":
            return .failed(summary: message.isEmpty
                ? "The core hit an unexpected error."
                : "The core hit an unexpected error: \(message)")
        case "workflow_error", "provider_error":
            return .failed(summary: message)
        default:
            return .failed(summary: message)
        }
    }

    private func finish(_ proposalID: String, _ state: CaretActionOffer.State) {
        executing.remove(proposalID)
        guard var offer = actionOffers[proposalID] else { return }
        offer.state = state
        actionOffers[proposalID] = offer
        onActionStateChange?(proposalID, state)
    }

    // MARK: - Events

    private func handle(_ event: CoreEvent) {
        switch event {
        case .offer(.inline(let offer)):
            let generation = generationForRevision[offer.revision] ?? -1
            onOffer?(InlineOffer(offer), generation)

        case .offer(.action(let offer)):
            var record = CaretActionOffer(
                proposalID: offer.proposalID,
                revision: offer.revision,
                target: offer.target,
                workflowID: offer.workflowID,
                title: offer.title,
                effect: offer.effect,
                evidence: offer.evidence,
                missingInputs: offer.missingInputs,
                executionMethod: offer.executionMethod,
                sampleOnly: offer.sampleOnly
            )
            if let reason = record.unavailabilityText {
                record.state = .unavailable(reason: reason)
            }
            actionOffers[offer.proposalID] = record
            // Workflow id and runnability only. The offer's text belongs to
            // the user and is never logged.
            log.info("action offer: \(offer.workflowID, privacy: .public) executable=\(record.isExecutable, privacy: .public) method=\(offer.executionMethod, privacy: .public)")
            onActionOffer?(record)
            onActionsChanged?()

        case .invalidated(let proposalID, let reason):
            // Blocker 5: dropping the record is not enough. The UI keeps its
            // own list and the key tap keeps its own choice count, so both
            // must be recomputed now or a dead row stays on screen and Cmd-1
            // still claims a key for an offer that no longer exists.
            let wasAction = actionOffers.removeValue(forKey: proposalID) != nil
            executing.remove(proposalID)
            if wasAction { onActionsChanged?() }
            onInvalidated?(proposalID, .invalidatedByCore)
            log.info("core invalidated a proposal: \(reason, privacy: .public)")

        case .failed(_, let reason):
            // The core reached us, so this is a provider or internal fault
            // rather than a dead process; either way nothing is retried here.
            // The next context change schedules the next attempt.
            unavailableText = "The completion backend failed: \(reason)"
            onUnavailable?(.providerError)

        case .abstain, .discarded:
            break

        case .unknown(let name):
            log.error("core sent an event this build does not know: \(name, privacy: .public)")
        }
    }
}

enum InlineProviderError: Error, Equatable {
    case notRunning
    case wrongResultKind
}
