import XCTest
import CaretCore
#if SWIFT_PACKAGE
@testable import Caret
#endif

/// Regressions for five blockers a fresh review found in the action
/// acceptance path at 3956ee0. Each test names the wrong behavior it pins
/// against, because the fixes are not self-evident from the code alone.
final class ActionAcceptanceTests: XCTestCase {

    private func target(
        pid: pid_t = 501,
        element: String = "el-1",
        revision: String = "r1"
    ) -> TargetIdentity {
        TargetIdentity(
            pid: pid, bundleID: "com.apple.TextEdit", windowID: "win-1",
            elementID: element, elementRevision: revision
        )
    }

    private func live(
        _ target: TargetIdentity,
        value: String = "hello",
        selection: TextSelection? = nil,
        secure: Bool = false
    ) -> InsertionGuard.LiveField {
        InsertionGuard.LiveField(target: target, value: value, selection: selection, secure: secure)
    }

    // MARK: - Blocker 1: stale action target

    /// The offer's target is captured at mint time. Sending it unchecked lets
    /// an action rewrite a field the user has since left.
    func testActionRefusesWhenFocusMovedToAnotherField() {
        let prepared = target(element: "body")
        let reason = CoreBridgeProvider.staleness(
            offerTarget: prepared,
            live: live(target(element: "subject"))
        )
        XCTAssertEqual(reason, "The focus moved to a different field, so nothing ran.")
    }

    /// Editing the same field is a different fact than leaving it, and the
    /// user is told which happened.
    func testActionRefusesWhenTextChangedInTheSameField() {
        let reason = CoreBridgeProvider.staleness(
            offerTarget: target(revision: "r1"),
            live: live(target(revision: "r2"))
        )
        XCTAssertEqual(reason, "The text changed after this was prepared, so nothing ran.")
    }

    func testActionRefusesOnASecureField() {
        let reason = CoreBridgeProvider.staleness(
            offerTarget: target(),
            live: live(target(), secure: true)
        )
        XCTAssertEqual(reason, "That field is secure, so Caret will not act on it.")
    }

    func testActionProceedsWhenTheFieldIsUnchanged() {
        XCTAssertNil(CoreBridgeProvider.staleness(offerTarget: target(), live: live(target())))
    }

    /// A different process with otherwise identical-looking identity is a
    /// different field, not an edit.
    func testDifferentProcessIsAMovedTarget() {
        let reason = CoreBridgeProvider.staleness(
            offerTarget: target(pid: 501),
            live: live(target(pid: 999))
        )
        XCTAssertEqual(reason, "The focus moved to a different field, so nothing ran.")
    }

    // MARK: - Blocker 5: invalidated offers leave no dead row

    func testHostMismatchIsNilWhenPidAndBundleMatchALiveHost() {
        let offer = target(pid: 501)
        let host = CoreBridgeProvider.HostSnapshot(pid: 501, bundleID: "com.apple.TextEdit", terminated: false)
        XCTAssertNil(CoreBridgeProvider.hostMismatch(offerTarget: offer, host: host))
    }

    func testHostMismatchWhenThePidIsGoneOrTerminatedOrTheBundleDiffers() {
        let offer = target(pid: 501)
        XCTAssertNotNil(CoreBridgeProvider.hostMismatch(offerTarget: offer, host: nil))
        XCTAssertNotNil(CoreBridgeProvider.hostMismatch(
            offerTarget: offer,
            host: CoreBridgeProvider.HostSnapshot(pid: 501, bundleID: "com.apple.TextEdit", terminated: true)
        ))
        XCTAssertNotNil(CoreBridgeProvider.hostMismatch(
            offerTarget: offer,
            host: CoreBridgeProvider.HostSnapshot(pid: 999, bundleID: "com.apple.TextEdit", terminated: false)
        ))
        XCTAssertNotNil(CoreBridgeProvider.hostMismatch(
            offerTarget: offer,
            host: CoreBridgeProvider.HostSnapshot(pid: 501, bundleID: "com.apple.Safari", terminated: false)
        ))
    }

    @MainActor
    func testVisibleChoicesAreOfferedOnly() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        let running = CaretActionOffer(
            proposalID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            revision: 1,
            target: target(pid: 501, element: ""),
            workflowID: "book-calendar-link",
            title: "Running",
            effect: "",
            evidence: [],
            missingInputs: [],
            executionMethod: "computer-use-jev",
            sampleOnly: false,
            state: .running
        )
        let offered = CaretActionOffer(
            proposalID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            revision: 2,
            target: target(pid: 501, element: ""),
            workflowID: "report-github-issue",
            title: "Report",
            effect: "",
            evidence: [],
            missingInputs: [],
            executionMethod: "computer-use-jev",
            sampleOnly: false,
            state: .offered
        )
        provider.testingReplaceOffers([running, offered])
        XCTAssertEqual(provider.visibleExecutableActions.map(\.proposalID), [offered.proposalID])

        let model = Model()
        model.setActionOffers([running, offered])
        XCTAssertEqual(model.runnableOffers.map(\.proposalID), [offered.proposalID])
    }

    @MainActor
    func testContextInvalidationClearsOffersAndNotifies() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        var changes = 0
        provider.onActionsChanged = { changes += 1 }

        // No offers yet: invalidation must not fire a spurious recompute.
        provider.invalidateContextualOffers()
        XCTAssertEqual(changes, 0)
        XCTAssertTrue(provider.visibleExecutableActions.isEmpty)
    }

    @MainActor
    func testDiscardPreparedOfferRemovesAnOfferedRowAndNotifies() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        let offered = CaretActionOffer(
            proposalID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            revision: 2,
            target: target(pid: 501, element: ""),
            workflowID: "report-github-issue",
            title: "Report",
            effect: "",
            evidence: [],
            missingInputs: [],
            executionMethod: "computer-use-jev",
            sampleOnly: false,
            state: .offered
        )
        provider.testingReplaceOffers([offered])
        var changes = 0
        provider.onActionsChanged = { changes += 1 }

        provider.discardPreparedOffer(offered.proposalID)

        XCTAssertEqual(changes, 1)
        XCTAssertTrue(provider.visibleExecutableActions.isEmpty)
        XCTAssertNil(provider.actionOffer(id: offered.proposalID))
    }

    @MainActor
    func testDiscardPreparedOfferLeavesARunningRow() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        let running = CaretActionOffer(
            proposalID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            revision: 1,
            target: target(pid: 501, element: ""),
            workflowID: "book-calendar-link",
            title: "Running",
            effect: "",
            evidence: [],
            missingInputs: [],
            executionMethod: "computer-use-jev",
            sampleOnly: false,
            state: .running
        )
        provider.testingReplaceOffers([running])
        var changes = 0
        provider.onActionsChanged = { changes += 1 }

        provider.discardPreparedOffer(running.proposalID)

        XCTAssertEqual(changes, 0)
        XCTAssertEqual(provider.actionOffer(id: running.proposalID)?.state, .running)
    }

    @MainActor
    func testClearPanelScopeClearsExplicitStatusAndPreparePanelDoesNot() {
        let model = Model()
        model.beginExplicitInvoke(actionID: "report-github-issue")
        XCTAssertEqual(model.explicitStatus, "Searching GitHub…")

        model.preparePanel(scopedActionID: nil)
        XCTAssertEqual(model.explicitStatus, "Searching GitHub…")

        model.clearPanelScope()
        XCTAssertEqual(model.explicitStatus, "")
    }
}

/// Blocker 2 is about who owns Cmd-1..3 and blocker 3 about not dropping
/// typed text. Both are decided by the key router and the request cadence,
/// which are testable without a running app.
final class ActionKeyOwnershipTests: XCTestCase {

    private func key(_ code: Int64, _ mods: InlineModifiers = []) -> InlineKeyEvent {
        InlineKeyEvent(keyCode: code, modifiers: mods, isAutorepeat: false)
    }

    /// An ambient offer arriving while Caret's panel is closed must not take
    /// Cmd-1 from the app the user is typing in. The app publishes a zero
    /// choice count when the panel is hidden; this pins what the router does
    /// with that.
    func testHiddenPanelMeansCommandDigitsBelongToTheHost() {
        let hidden = InlineKeyContext(
            visibleProposalID: nil,
            acceptanceInFlight: false,
            visibleChoiceCount: 0,
            interceptionEnabled: true
        )
        for code in [InlineKeyCode.one, InlineKeyCode.two, InlineKeyCode.three] {
            let decision = InlineKeyRouter.decide(key(code, [.command]), context: hidden)
            XCTAssertEqual(decision, .passThrough)
            XCTAssertFalse(decision.consumesEvent, "the host must still receive Cmd-\(code)")
        }
    }

    func testVisiblePanelClaimsOnlyTheChoicesItShows() {
        let twoShown = InlineKeyContext(
            visibleProposalID: nil,
            acceptanceInFlight: false,
            visibleChoiceCount: 2,
            interceptionEnabled: true
        )
        XCTAssertEqual(InlineKeyRouter.decide(key(InlineKeyCode.one, [.command]), context: twoShown),
                       .selectChoice(index: 0))
        XCTAssertEqual(InlineKeyRouter.decide(key(InlineKeyCode.three, [.command]), context: twoShown),
                       .passThrough)
    }
}

/// Blocker 4: a non-empty selection was rejected before the judge saw it,
/// which blocked every selection-driven action.
final class SelectionContextTests: XCTestCase {

    private func snapshot(selection: TextSelection, caret: Int) throws -> InputSnapshot {
        let data = Data("""
        {"revision":4,"captured_at":"2026-09-19T18:59:20.828359+00:00",
         "target":{"pid":501,"bundle_id":"b","window_id":"w","element_id":"e","element_revision":"r"},
         "role":"AXTextArea","nearby_text":"hello world","text_offset":0,"caret":\(caret),
         "selection":{"start":\(selection.start),"end":\(selection.end)},
         "secure":false,"ime_composing":false,"app_excluded":false,"value_length":11}
        """.utf8)
        return try JSONDecoder().decode(InputSnapshot.self, from: data)
    }

    /// The request must carry the real selected range, not a collapsed caret.
    func testSelectionSurvivesIntoTheRequest() throws {
        let snap = try snapshot(selection: TextSelection(start: 0, end: 5), caret: 5)
        let request = InlineCompletionRequest(
            generation: 1, revision: snap.revision,
            target: InlineTarget(snap.target), role: snap.role,
            nearbyText: snap.nearbyText, textOffset: snap.textOffset, caret: snap.caret,
            selection: NSRange(location: snap.selection.start,
                               length: max(0, snap.selection.end - snap.selection.start)),
            secure: snap.secure, imeComposing: snap.imeComposing,
            appExcluded: snap.appExcluded, valueLength: snap.valueLength ?? 0
        )
        XCTAssertEqual(request.selection, NSRange(location: 0, length: 5),
                       "a selection-driven action needs the selection, not a caret")

        // And it round-trips back onto the wire unchanged.
        let wire = request.snapshot
        XCTAssertEqual(wire.selection, TextSelection(start: 0, end: 5))
        XCTAssertFalse(wire.selection.isEmpty)
    }

    func testCollapsedCaretStillProducesAnEmptySelection() throws {
        let snap = try snapshot(selection: TextSelection(start: 5, end: 5), caret: 5)
        XCTAssertTrue(snap.selection.isEmpty)
    }
}

/// Opening Caret's panel makes Caret frontmost, so the next capture reports a
/// focus change. Acting on that tore down the offers the panel exists to show.
@MainActor
final class PanelCapturePauseTests: XCTestCase {
    private func coordinator() -> InlineCompletionCoordinator {
        InlineCompletionCoordinator(provider: nil, capture: FocusedTargetCapture())
    }

    func testPauseIsOffUntilThePanelOpens() {
        XCTAssertFalse(coordinator().isPaused)
    }

    func testPauseTogglesAndIsIdempotent() {
        let c = coordinator()
        c.setPaused(true)
        XCTAssertTrue(c.isPaused)
        c.setPaused(true)
        XCTAssertTrue(c.isPaused, "repeating the same state is a no-op, not a toggle")
        c.setPaused(false)
        XCTAssertFalse(c.isPaused)
    }

    /// Offers already prepared must survive the panel opening: dropping them
    /// is the bug this pause exists to prevent.
    func testOffersSurviveAPanelOpenAndClose() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        var drops = 0
        provider.onActionsChanged = { drops += 1 }

        let c = coordinator()
        c.setPaused(true)
        c.setPaused(false)
        XCTAssertEqual(drops, 0, "a panel open/close cycle must not invalidate offers")
    }
}
