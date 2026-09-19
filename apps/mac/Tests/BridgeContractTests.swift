import XCTest
import CaretCore
#if SWIFT_PACKAGE
@testable import Caret
#endif

/// Decoding against the timestamp shapes the real Python core emits.
///
/// The core builds created_at from datetime.now(timezone.utc).isoformat(),
/// which carries six fractional digits. A formatter built with
/// .withInternetDateTime alone parses "+00:00" and still returns nil for
/// ".828359+00:00", so every live offer would arrive undecodable while whole
/// second fixtures kept passing. That is the case this pins.
final class BridgeContractTests: XCTestCase {
    private func offerLine(createdAt: String) -> Data {
        Data("""
        {"event":"offer","offer":{"kind":"inline","proposal_id":"p1","revision":7,
        "target":{"pid":501,"bundle_id":"com.apple.TextEdit","window_id":"win-1",
        "element_id":"el-1","element_revision":"abc123"},
        "created_at":"\(createdAt)","replace_start":16,"replace_end":16,
        "replacement":" summary to the team","original_digest":"e3b0c44298fc1c14"}}
        """.utf8)
    }

    private struct Line: Decodable { let offer: Offer }

    func testDecodesFractionalSecondTimestampFromRealCore() throws {
        let line = try JSONDecoder().decode(Line.self, from: offerLine(createdAt: "2026-09-19T18:59:20.828359+00:00"))
        guard case .inline(let offer) = line.offer else { return XCTFail("expected an inline offer") }
        XCTAssertEqual(offer.proposalID, "p1")
        XCTAssertEqual(offer.replaceStart, 16)
    }

    func testDecodesWholeSecondAndZuluForms() throws {
        for stamp in ["2026-09-19T18:59:20+00:00", "2026-09-19T18:59:20Z", "2026-09-19T18:59:20.828359Z"] {
            let line = try JSONDecoder().decode(Line.self, from: offerLine(createdAt: stamp))
            guard case .inline = line.offer else { return XCTFail("expected an inline offer for \(stamp)") }
        }
    }

    /// An offer event carries no "status"; only the accept result does.
    func testOfferDecodesWithoutStatusField() throws {
        let line = try JSONDecoder().decode(Line.self, from: offerLine(createdAt: "2026-09-19T18:59:20.1+00:00"))
        guard case .inline(let offer) = line.offer else { return XCTFail("expected an inline offer") }
        XCTAssertEqual(offer.originalDigest, "e3b0c44298fc1c14")
    }

    /// A caret insertion digests the empty replaced span, which is why the
    /// protocol sample looks like a placeholder and is not one.
    func testInsertionDigestsTheEmptyReplacedSpan() {
        XCTAssertEqual(UTF16Text.digest(""), "e3b0c44298fc1c14")
    }

    /// The app must round-trip its own offer into the shape the guard reads.
    func testCoreEditRoundTripsThroughTheWireEncoding() throws {
        let target = InlineTarget(pid: 501, bundleID: "b", windowID: "win-1", elementID: "el-1", elementRevision: "r")
        let offer = Caret.InlineOffer(
            proposalID: "p1", revision: 3, target: target,
            replaceStart: 5, replaceEnd: 5, replacement: " world",
            originalDigest: UTF16Text.digest(""), createdAt: Date()
        )
        let edit = try XCTUnwrap(offer.coreEdit)
        XCTAssertEqual(edit.proposalID, "p1")
        XCTAssertEqual(edit.target.elementID, "el-1")
        XCTAssertEqual(edit.replaceStart, 5)
        XCTAssertNil(edit.status, "an offer-derived edit carries no status")
    }

    /// A catalog entry is describable but not runnable, so it must never be
    /// presented as a choice Cmd-1 can execute.
    func testCatalogEntryIsNotExecutable() {
        var offer = CaretActionOffer(
            proposalID: "a1", revision: 1,
            target: TargetIdentity(pid: 1, bundleID: "b", windowID: "w", elementID: "e", elementRevision: "r"),
            workflowID: "book-flight", title: "Book flight", effect: "", evidence: [],
            missingInputs: [], executionMethod: "", sampleOnly: true
        )
        XCTAssertFalse(offer.isExecutable)
        XCTAssertNotNil(offer.unavailabilityText)

        offer.sampleOnly = false
        XCTAssertFalse(offer.isExecutable, "no execution method is still not runnable")

        offer.executionMethod = "adapter"
        offer.missingInputs = ["calendar"]
        XCTAssertFalse(offer.isExecutable, "a missing input is not runnable")
        XCTAssertEqual(offer.unavailabilityText, "Needs calendar before it can run.")

        offer.missingInputs = []
        XCTAssertTrue(offer.isExecutable)
        XCTAssertNil(offer.unavailabilityText)
    }

    /// The codes mean different things to a user: a refused acceptance means
    /// nothing ran, a workflow error means it ran and failed, and
    /// internal_error means the core itself broke. Collapsing them would tell
    /// the user a workflow failed when it never started.
    func testErrorCodesMapToDistinctStates() {
        func state(_ code: String, _ message: String = "boom") -> CaretActionOffer.State {
            CoreBridgeProvider.actionState(for: BridgeError.core(code: code, message: message))
        }

        guard case .unavailable = state("acceptance_rejected") else {
            return XCTFail("a refused acceptance must not read as a failed run")
        }
        guard case .failed(let workflow) = state("workflow_error") else {
            return XCTFail("workflow_error is a failed run")
        }
        XCTAssertEqual(workflow, "boom")

        guard case .failed(let internalSummary) = state("internal_error") else {
            return XCTFail("internal_error displays as a failure")
        }
        XCTAssertTrue(
            internalSummary.contains("unexpected"),
            "internal_error should say the core broke, not blame a provider"
        )

        guard case .failed = state("provider_error") else {
            return XCTFail("provider_error is a failed run")
        }
    }

    /// A transport death is not a core error code and must not be reported as
    /// one.
    func testTransportFailureIsNotACoreCode() {
        guard case .failed(let summary) = CoreBridgeProvider.actionState(for: BridgeError.notRunning) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(summary.contains("stopped responding"))
    }

    private func offer(_ id: String, method: String, sampleOnly: Bool, missing: [String] = []) -> CaretActionOffer {
        CaretActionOffer(
            proposalID: "p-\(id)", revision: 1,
            target: TargetIdentity(pid: 1, bundleID: "b", windowID: "w", elementID: "e", elementRevision: "r"),
            workflowID: id, title: id, effect: "", evidence: [],
            missingInputs: missing, executionMethod: method, sampleOnly: sampleOnly
        )
    }

    /// These three are the catalog the real core returned from workflows.list
    /// on 2026-09-19. None of them is runnable, and the reason differs, so the
    /// app must not present any of them as a choice Cmd-1 can execute.
    func testLiveCatalogEntriesAreAllUnavailable() {
        let calendarLink = offer("book-calendar-link", method: "local-sample-planner", sampleOnly: true)
        XCTAssertFalse(calendarLink.isExecutable)
        XCTAssertEqual(calendarLink.unavailabilityText, "Sample only. book-calendar-link has no live executor yet.")

        // The one a non-empty check would have got wrong.
        let flight = offer("book-flight", method: "unwired", sampleOnly: false)
        XCTAssertFalse(flight.isExecutable, "\"unwired\" names the absence of an executor")
        XCTAssertEqual(flight.unavailabilityText, "book-flight is described but not wired to an executor yet.")

        let revise = offer("revise", method: "unwired", sampleOnly: false)
        XCTAssertFalse(revise.isExecutable)
    }

    func testPlaceholderMethodIsCaseAndWhitespaceInsensitive() {
        XCTAssertFalse(offer("x", method: "  Unwired ", sampleOnly: false).isExecutable)
    }

    /// A genuinely wired adapter with everything present is runnable; the
    /// guard must not be so broad that nothing can ever run.
    func testRealAdapterIsExecutable() {
        let wired = offer("meeting", method: "live-calendar-adapter", sampleOnly: false)
        XCTAssertTrue(wired.isExecutable)
        XCTAssertNil(wired.unavailabilityText)
    }


    private func execution(_ status: String, _ summary: String = "s", _ evidence: [String] = []) throws -> WorkflowExecution {
        let data = Data("""
        {"status":"\(status)","summary":"\(summary)","evidence":\(evidence.isEmpty ? "[]" : "[\"\(evidence[0])\"]")}
        """.utf8)
        return try JSONDecoder().decode(WorkflowExecution.self, from: data)
    }

    /// book-calendar-link returns status "completed" with execution_method
    /// "draft_only": it produced draft text and explicitly did not send a
    /// message or create a calendar event. Labelling that "Done" would tell
    /// the user a meeting was scheduled.
    func testDraftOnlyCompletionIsNotLabelledDone() throws {
        let state = CoreBridgeProvider.actionState(
            for: try execution("completed", "Drafted 3 meeting time(s) for review."),
            scope: .draftOnly
        )
        guard case .succeeded(let summary, _, let scope) = state else {
            return XCTFail("completed is a finished run")
        }
        XCTAssertEqual(scope, .draftOnly)
        XCTAssertEqual(scope.label, "Draft ready")
        XCTAssertNotEqual(scope.label, "Done")
        XCTAssertEqual(summary, "Drafted 3 meeting time(s) for review.", "summary is shown verbatim")
    }

    func testExternalEffectCompletionIsLabelledDone() throws {
        let state = CoreBridgeProvider.actionState(for: try execution("completed"), scope: .externalEffect)
        guard case .succeeded(_, _, let scope) = state else { return XCTFail("expected success") }
        XCTAssertEqual(scope.label, "Done")
    }

    /// The core permits exactly completed, needs_input, failed and cancelled.
    func testTheFourPermittedStatusesMapDistinctly() throws {
        guard case .unavailable = CoreBridgeProvider.actionState(for: try execution("needs_input"), scope: .externalEffect) else {
            return XCTFail("needs_input is not a success and not a failure")
        }
        guard case .cancelled = CoreBridgeProvider.actionState(for: try execution("cancelled"), scope: .externalEffect) else {
            return XCTFail("cancelled is not a failure")
        }
        guard case .failed = CoreBridgeProvider.actionState(for: try execution("failed"), scope: .externalEffect) else {
            return XCTFail("failed is a failure")
        }
    }

    /// A status outside the contract is surfaced, not quietly treated as one
    /// of the four.
    func testUnrecognizedStatusSaysSo() throws {
        guard case .failed(let summary) = CoreBridgeProvider.actionState(for: try execution("succeeded"), scope: .externalEffect) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(summary.contains("unrecognized"), "a contract change must be visible, got: \(summary)")
    }

    /// draft_only and skyvern_browser are real execution methods, not
    /// placeholders; the unwired guard must not swallow them.
    func testRealExecutionMethodsAreNotTreatedAsPlaceholders() {
        XCTAssertTrue(offer("cal", method: "draft_only", sampleOnly: false).isExecutable)
        XCTAssertTrue(offer("flight", method: "skyvern_browser", sampleOnly: false).isExecutable)
        XCTAssertEqual(offer("cal", method: "draft_only", sampleOnly: false).completionScope, .draftOnly)
        XCTAssertEqual(offer("flight", method: "skyvern_browser", sampleOnly: false).completionScope, .externalEffect)
    }


    /// The adapter's no-effect disclosure is the sentence that stops a draft
    /// reading as a booking. It must survive whatever row cap the UI applies.
    func testDraftOnlyEvidenceIsNeverCapped() {
        let disclosure = "Returned the approved draft text only. No message was sent, and no calendar event was created, held or modified."
        let evidence = ["one", "two", "three", "four", "five", disclosure]

        let draft = CaretActionOffer.visibleEvidence(evidence, scope: .draftOnly)
        XCTAssertEqual(draft.count, evidence.count, "a draft-only run shows all evidence")
        XCTAssertTrue(draft.contains(disclosure), "the no-effect disclosure must not be dropped")
        XCTAssertGreaterThan(disclosure.count, 100, "fixture must be long enough to exercise the wrap")

        // Ordinary runs may still be capped; nothing load-bearing is lost.
        XCTAssertEqual(CaretActionOffer.visibleEvidence(evidence, scope: .externalEffect).count, 4)
    }

    /// Offers come only from core-minted offer events. The app never turns a
    /// workflows.list catalog entry into something the user can run, so the
    /// registry's exclusion of unavailable adapters stays the invariant.
    @MainActor
    func testCatalogEntriesAreNotSynthesizedIntoOffers() {
        let provider = CoreBridgeProvider(capture: FocusedTargetCapture())
        XCTAssertTrue(provider.visibleExecutableActions.isEmpty,
                      "no offers exist until the core mints one")
    }
}

/// The launch preflight. A missing provider key is the most likely reason the
/// demo does not start, and the core names it on stderr then exits -- but
/// CaretCore counts stderr and never logs it, so that name cannot reach the
/// user unless it is checked here first.
final class CoreLaunchSettingsTests: XCTestCase {
    func testEachProviderNamesItsOwnKey() {
        XCTAssertEqual(CoreLaunchSettings.requiredKey(forProvider: "gateway"), "AI_GATEWAY_API_KEY")
        XCTAssertEqual(CoreLaunchSettings.requiredKey(forProvider: "groq"), "GROQ_API_KEY")
        // TYPESAFE_API_KEY is the Jev key, not an old name for the others.
        XCTAssertEqual(CoreLaunchSettings.requiredKey(forProvider: "jev"), "TYPESAFE_API_KEY")
    }

    /// A scripted provider replays a recording and needs no key. It must not
    /// be reported as misconfigured.
    func testScriptedProviderNeedsNoKey() {
        XCTAssertNil(CoreLaunchSettings.requiredKey(forProvider: "scripted:/tmp/a.json"))
    }

    func testProviderIsReadFromTheFlagThatSelectsIt() {
        let args = ["--judge", "gateway", "--writer", "groq", "--adapter", "caret.live_workflows:MeetingDraftWorkflow"]
        XCTAssertEqual(CoreLaunchSettings.provider(named: "--judge", in: args), "gateway")
        XCTAssertEqual(CoreLaunchSettings.provider(named: "--writer", in: args), "groq")
        XCTAssertNil(CoreLaunchSettings.provider(named: "--missing", in: args))
    }

    /// A trailing flag with no value must not read the next thing along, or a
    /// malformed config would silently select the wrong provider.
    func testDanglingFlagYieldsNoProvider() {
        XCTAssertNil(CoreLaunchSettings.provider(named: "--judge", in: ["--writer", "groq", "--judge"]))
    }

    /// The env file parser returns names and values for the child's
    /// environment; it must tolerate comments, quotes and blank values without
    /// inventing entries.
    func testEnvFileParsingIsStrict() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("caret-env-\(UUID().uuidString)")
        try """
        # comment
        GROQ_API_KEY=abc123
        AI_GATEWAY_API_KEY="quoted-value"
        EMPTY=
        malformed-line
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = CoreLaunchSettings.environment(fromEnvFileAt: url.path)
        XCTAssertEqual(parsed["GROQ_API_KEY"], "abc123")
        XCTAssertEqual(parsed["AI_GATEWAY_API_KEY"], "quoted-value", "surrounding quotes are stripped")
        XCTAssertNil(parsed["EMPTY"], "a blank value is not a configured key")
        XCTAssertEqual(parsed.count, 2)
    }

    func testMissingEnvFileIsEmptyNotACrash() {
        XCTAssertTrue(CoreLaunchSettings.environment(fromEnvFileAt: "/nonexistent/caret.env").isEmpty)
        XCTAssertTrue(CoreLaunchSettings.environment(fromEnvFileAt: nil).isEmpty)
    }

    /// Each failure names the thing to change. A dead process with no reason
    /// is what this exists to prevent.
    func testUnavailableReasonsAreActionable() {
        XCTAssertTrue(CoreLaunchSettings.Unavailable
            .missingKey(variable: "AI_GATEWAY_API_KEY", provider: "judge gateway")
            .statusText.contains("AI_GATEWAY_API_KEY"))
        XCTAssertTrue(CoreLaunchSettings.Unavailable.judgeNotSelected.statusText.contains("jev"),
                      "the user needs to know which judge they would silently get")
        XCTAssertTrue(CoreLaunchSettings.Unavailable.noInterpreter.statusText.contains("dev.json"))
    }

    func testDiscoveredPythonUsesFirstExecutableInDocumentedPriority() throws {
        let documentedPriority = [
            "/opt/homebrew/bin/python3.14",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/usr/bin/python3",
        ]
        guard let expected = documentedPriority.first(where: FileManager.default.isExecutableFile) else {
            throw XCTSkip("No documented Python installation on this runner")
        }
        XCTAssertEqual(CoreLaunchSettings.discoveredPythonExecutable(), expected)
    }
}

/// The demo argv. Gateway 403s on this team (customer_verification_required),
/// and the core reports that as a failed tick with no offer and no fallback,
/// so defaulting to it would ship an app that silently never completes.
final class DemoLaunchArgvTests: XCTestCase {
    func testPatternJudgeNeedsNoKey() {
        XCTAssertNil(CoreLaunchSettings.requiredKey(forProvider: "pattern"),
                     "the deterministic judge consumes no credential")
    }

    /// The writer stays real: inline completions are generated by Groq, not
    /// pattern-matched, so the demo is not synthetic end to end.
    func testGroqWriterStillRequiresItsKey() {
        XCTAssertEqual(CoreLaunchSettings.requiredKey(forProvider: "groq"), "GROQ_API_KEY")
    }

    /// Gateway remains selectable and still preflights its key, so turning it
    /// back on after the account is verified needs no code change.
    func testGatewayRemainsAvailableWithItsKey() {
        XCTAssertEqual(CoreLaunchSettings.requiredKey(forProvider: "gateway"), "AI_GATEWAY_API_KEY")
    }
}
