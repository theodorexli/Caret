import XCTest
@testable import CaretCore

final class CoreBridgeClientTests: XCTestCase {
    private func startedClient() throws -> (CoreBridgeClient, FakeTransport) {
        let transport = FakeTransport()
        let client = CoreBridgeClient(transport: transport)
        try client.start()
        return (client, transport)
    }

    // MARK: - Requests and replies

    func testRequestCarriesIDAndMethodAndResolvesOnMatchingReply() async throws {
        let (client, transport) = try startedClient()

        async let reply = client.hello()
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        XCTAssertEqual(transport.lastSentMethod(), "hello")

        transport.emit(line: """
        {"id":\(id),"ok":true,"result":{"protocol":1,"interval_seconds":2.0,\
        "max_offer_age_seconds":30.0,"max_inline_units":120,"workflows":[]}}
        """)

        let hello = try await reply
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.intervalSeconds, 2.0)
        XCTAssertEqual(hello.maxInlineUnits, 120)
    }

    func testContextUpdateSendsTheDocumentedFrameShape() async throws {
        let (client, transport) = try startedClient()

        async let reply = client.updateContext(Fixtures.frame())
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        transport.emit(line: #"{"id":\#(id),"ok":true,"result":{"status":"admitted","reason":"","revision":7}}"#)

        let result = try await reply
        XCTAssertEqual(result.status, .admitted)
        XCTAssertEqual(result.revision, 7)

        let sent = transport.sentObject(at: 0)
        let params = sent?["params"] as? [String: Any]
        let frame = params?["frame"] as? [String: Any]
        let snapshot = frame?["snapshot"] as? [String: Any]
        XCTAssertEqual(sent?["method"] as? String, "context.update")
        XCTAssertEqual(snapshot?["nearby_text"] as? String, "I will send the ")
        XCTAssertEqual(snapshot?["text_offset"] as? Int, 0)
        XCTAssertEqual(snapshot?["caret"] as? Int, 16)
        XCTAssertEqual((snapshot?["selection"] as? [String: Any])?["start"] as? Int, 16)
        XCTAssertEqual((snapshot?["target"] as? [String: Any])?["bundle_id"] as? String, "com.example.Editor")
        XCTAssertEqual((snapshot?["target"] as? [String: Any])?["element_revision"] as? String, "v7")
        // captured_at must carry an offset; the core rejects a naive timestamp.
        let capturedAt = snapshot?["captured_at"] as? String ?? ""
        XCTAssertTrue(capturedAt.hasSuffix("Z") || capturedAt.contains("+"), capturedAt)
        // An unavailable clipboard is an explicit false, never empty text.
        let clipboard = frame?["clipboard"] as? [String: Any]
        XCTAssertEqual(clipboard?["available"] as? Bool, false)
        XCTAssertNil(clipboard?["text"])
    }

    func testPrepareWorkflowEncodesTheFrameAndDecodesTheOffer() async throws {
        let (client, transport) = try startedClient()

        async let reply = client.prepareWorkflow(workflowID: "report-github-issue", frame: Fixtures.frame())
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        let sent = try XCTUnwrap(transport.sentObject(at: 0))
        XCTAssertEqual(sent["method"] as? String, "workflow.prepare")
        let params = try XCTUnwrap(sent["params"] as? [String: Any])
        XCTAssertEqual(params["workflow_id"] as? String, "report-github-issue")
        XCTAssertNotNil(params["frame"])

        transport.emit(line: """
        {"id":\(id),"ok":true,"result":{"offer":{"kind":"action","proposal_id":"p-explicit","revision":3,\
        "target":{"pid":4242,"bundle_id":"com.example.Editor","window_id":"","element_id":"",\
        "element_revision":""},"workflow_id":"report-github-issue","title":"Open a GitHub issue",\
        "effect":"Nothing until accept.","evidence":["No matching public issue was found."],\
        "required_inputs":[],"missing_inputs":[],"execution_method":"computer-use-jev","sample_only":false}}}
        """)

        let offer = try await reply
        XCTAssertEqual(offer.proposalID, "p-explicit")
        XCTAssertEqual(offer.workflowID, "report-github-issue")
        XCTAssertEqual(offer.executionMethod, "computer-use-jev")
        XCTAssertTrue(offer.missingInputs.isEmpty)
        XCTAssertFalse(offer.sampleOnly)
    }

    func testPrepareWorkflowSurfacesAWorkflowError() async throws {
        let (client, transport) = try startedClient()

        async let reply = client.prepareWorkflow(workflowID: "report-github-issue", frame: Fixtures.frame())
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        transport.emit(line: #"{"id":\#(id),"ok":false,"error":{"code":"workflow_error","message":"This does not appear to be an open-source application."}}"#)

        do {
            _ = try await reply
            XCTFail("expected the coded error to surface")
        } catch let error as BridgeError {
            XCTAssertEqual(error, .core(code: "workflow_error", message: "This does not appear to be an open-source application."))
        }
    }

    func testCodedErrorReplyBecomesATypedError() async throws {
        let (client, transport) = try startedClient()

        async let reply = client.accept(proposalID: "p1", revision: 7, target: Fixtures.target)
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        transport.emit(line: #"{"id":\#(id),"ok":false,"error":{"code":"acceptance_rejected","message":"already accepted"}}"#)

        do {
            _ = try await reply
            XCTFail("expected the coded error to surface")
        } catch let error as BridgeError {
            XCTAssertEqual(error, .core(code: "acceptance_rejected", message: "already accepted"))
        }
    }

    func testAcceptDecodesAnInlineEditAndDismissDecodesItsFlag() async throws {
        let (client, transport) = try startedClient()

        async let accepted = client.accept(proposalID: "p1", revision: 7, target: Fixtures.target)
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        transport.emit(line: """
        {"id":\(id),"ok":true,"result":{"kind":"inline","proposal_id":"p1","status":"ready_to_insert",\
        "target":{"pid":4242,"bundle_id":"com.example.Editor","window_id":"w1","element_id":"compose",\
        "element_revision":"v7"},"replace_start":16,"replace_end":16,\
        "replacement":" summary to the team","original_digest":"e3b0c44298fc1c14"}}
        """)

        guard case .inline(let edit) = try await accepted else { return XCTFail("expected an inline edit") }
        XCTAssertEqual(edit.replaceStart, 16)
        XCTAssertEqual(edit.replaceEnd, 16)
        XCTAssertEqual(edit.replacement, " summary to the team")
        XCTAssertEqual(edit.originalDigest, "e3b0c44298fc1c14")
    }

    func testRepliesOutOfOrderReachTheRightWaiters() async throws {
        let (client, transport) = try startedClient()

        async let first = client.updateContext(Fixtures.frame(revision: 7))
        _ = transport.awaitRequest()
        async let second = client.updateContext(Fixtures.frame(revision: 8, nearbyText: "another window"))
        // Wait until both requests are on the wire.
        let deadline = Date().addingTimeInterval(2)
        while transport.sentLines.count < 2, Date() < deadline { usleep(2000) }
        XCTAssertEqual(transport.sentLines.count, 2)

        transport.emit(line: #"{"id":2,"ok":true,"result":{"status":"coalesced","reason":"in-interval","revision":8}}"#)
        transport.emit(line: #"{"id":1,"ok":true,"result":{"status":"admitted","reason":"","revision":7}}"#)

        let (one, two) = try await (first, second)
        XCTAssertEqual(one.revision, 7)
        XCTAssertEqual(one.status, .admitted)
        XCTAssertEqual(two.revision, 8)
        XCTAssertEqual(two.status, .coalesced)
    }

    // MARK: - Events

    func testUnsolicitedEventsAreDeliveredWhileARequestIsInFlight() async throws {
        let transport = FakeTransport()
        let client = CoreBridgeClient(transport: transport)
        let received = Received()
        client.onEvent { received.append($0) }
        try client.start()

        async let reply = client.updateContext(Fixtures.frame())
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }

        transport.emit(line: """
        {"event":"offer","offer":{"kind":"inline","proposal_id":"p1","revision":7,\
        "target":{"pid":4242,"bundle_id":"com.example.Editor","window_id":"w1","element_id":"compose",\
        "element_revision":"v7"},"created_at":"2026-09-19T12:00:00Z","replace_start":16,"replace_end":16,\
        "replacement":" summary","original_digest":"e3b0c44298fc1c14"}}
        """)
        transport.emit(line: #"{"event":"abstain","revision":8,"reason":"judge-abstained"}"#)
        transport.emit(line: #"{"event":"invalidated","proposal_id":"p1","reason":"context-changed"}"#)
        transport.emit(line: #"{"event":"discarded","revision":6,"reason":"stale-snapshot"}"#)
        transport.emit(line: #"{"event":"failed","revision":9,"reason":"judge/route: HTTP 401"}"#)
        transport.emit(line: #"{"id":\#(id),"ok":true,"result":{"status":"admitted","reason":"","revision":7}}"#)

        _ = try await reply
        let events = received.all()
        XCTAssertEqual(events.count, 5)
        guard case .offer(let offer) = events[0] else { return XCTFail("expected an offer") }
        XCTAssertEqual(offer.proposalID, "p1")
        XCTAssertEqual(offer.revision, 7)
        XCTAssertEqual(offer.target, Fixtures.target)
        guard case .inline(let inline) = offer else { return XCTFail("expected an inline offer") }
        XCTAssertEqual(inline.replacement, " summary")
        XCTAssertEqual(events[1], .abstain(revision: 8, reason: "judge-abstained"))
        XCTAssertEqual(events[2], .invalidated(proposalID: "p1", reason: "context-changed"))
        XCTAssertEqual(events[3], .discarded(revision: 6, reason: "stale-snapshot"))
        XCTAssertEqual(events[4], .failed(revision: 9, reason: "judge/route: HTTP 401"))
    }

    func testActionOfferDecodesItsWorkflowFields() throws {
        let transport = FakeTransport()
        let client = CoreBridgeClient(transport: transport)
        let received = Received()
        client.onEvent { received.append($0) }
        try client.start()

        transport.emit(line: """
        {"event":"offer","offer":{"kind":"action","proposal_id":"p2","revision":9,\
        "target":{"pid":4242,"bundle_id":"com.example.Editor","window_id":"w1","element_id":"compose",\
        "element_revision":"v7"},"workflow_id":"schedule","title":"Schedule the sync",\
        "effect":"Creates a calendar event","evidence":["from the thread"],"required_inputs":["attendees"],\
        "missing_inputs":[],"execution_method":"scheduler.rpc","sample_only":true}}
        """)

        guard case .offer(.action(let offer)) = received.all().first else { return XCTFail("expected an action offer") }
        XCTAssertEqual(offer.workflowID, "schedule")
        XCTAssertEqual(offer.title, "Schedule the sync")
        XCTAssertEqual(offer.evidence, ["from the thread"])
        XCTAssertTrue(offer.sampleOnly)
    }

    func testUnknownEventNameIsKeptRatherThanDropped() throws {
        let transport = FakeTransport()
        let client = CoreBridgeClient(transport: transport)
        let received = Received()
        client.onEvent { received.append($0) }
        try client.start()

        transport.emit(line: #"{"event":"rehearsing","revision":3,"reason":""}"#)
        XCTAssertEqual(received.all(), [.unknown(name: "rehearsing")])
    }

    // MARK: - Framing

    func testPartialAndCoalescedLinesAreReassembled() async throws {
        let transport = FakeTransport()
        let client = CoreBridgeClient(transport: transport)
        let received = Received()
        client.onEvent { received.append($0) }
        try client.start()

        async let reply = client.updateContext(Fixtures.frame())
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }

        // One reply split across three chunks, with an event packed into the
        // same chunk as the reply's tail.
        transport.emit(chunk: #"{"id":\#(id),"ok":true,"#)
        transport.emit(chunk: #""result":{"status":"admit"#)
        transport.emit(chunk: "ted\",\"reason\":\"\",\"revision\":7}}\n{\"event\":\"abstain\",\"revision\":8,\"reason\":\"judge-abstained\"}\n")

        let result = try await reply
        XCTAssertEqual(result.status, .admitted)
        XCTAssertEqual(received.all(), [.abstain(revision: 8, reason: "judge-abstained")])
    }

    func testAccumulatorHandlesBlankLinesAndSplitMultibyteCharacters() {
        var accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(Data("\n\n".utf8)), [])

        // "é" is two UTF-8 bytes; split them across chunks.
        let bytes = Array(#"{"event":"abstain","reason":"é"}"#.utf8)
        let split = bytes.count - 3
        XCTAssertEqual(accumulator.append(Data(bytes[..<split])), [])
        XCTAssertEqual(
            accumulator.append(Data(bytes[split...] + Array("\n".utf8))),
            [#"{"event":"abstain","reason":"é"}"#]
        )
        XCTAssertNil(accumulator.flush())
    }

    func testAccumulatorReturnsATrailingLineOnFlush() {
        var accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(Data("{\"a\":1}".utf8)), [])
        XCTAssertEqual(accumulator.flush(), "{\"a\":1}")
    }

    // MARK: - Lifecycle

    func testProcessExitFailsEveryInFlightRequest() async throws {
        let (client, transport) = try startedClient()

        async let first = client.hello()
        _ = transport.awaitRequest()
        async let second = client.updateContext(Fixtures.frame())
        let deadline = Date().addingTimeInterval(2)
        while transport.sentLines.count < 2, Date() < deadline { usleep(2000) }

        transport.terminate(status: 3)

        do {
            _ = try await first
            XCTFail("expected the exit to fail the first request")
        } catch let error as BridgeError {
            guard case .processExited(let status, _) = error else {
                return XCTFail("expected processExited, got \(error)")
            }
            XCTAssertEqual(status, 3)
        }
        do {
            _ = try await second
            XCTFail("expected the exit to fail the second request")
        } catch let error as BridgeError {
            guard case .processExited = error else { return XCTFail("expected processExited, got \(error)") }
        }
        XCTAssertEqual(client.currentState, .stopped(.exited(status: 3)))
    }

    func testRequestAfterExitFailsImmediatelyWithoutHanging() async throws {
        let (client, transport) = try startedClient()
        transport.terminate(status: 0)

        do {
            _ = try await client.hello()
            XCTFail("expected the request to be refused")
        } catch let error as BridgeError {
            guard case .processExited = error else { return XCTFail("expected processExited, got \(error)") }
        }
        XCTAssertTrue(transport.sentLines.isEmpty)
    }

    func testStartingTwiceIsRefused() throws {
        let (client, _) = try startedClient()
        XCTAssertThrowsError(try client.start()) { error in
            XCTAssertEqual(error as? BridgeError, .alreadyRunning)
        }
    }

    func testCancellingARequestReleasesItsWaiter() async throws {
        let (client, transport) = try startedClient()

        let task = Task { try await client.hello() }
        _ = transport.awaitRequest()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected the cancellation to surface")
        } catch let error as BridgeError {
            XCTAssertEqual(error, .cancelled)
        }

        // A late reply to the cancelled id must not resolve anything or crash.
        transport.emit(line: #"{"id":1,"ok":true,"result":{"protocol":1,"interval_seconds":2.0,"max_offer_age_seconds":30.0,"max_inline_units":120,"workflows":[]}}"#)
    }

    func testShutdownSendsTheVerbAndStopsTheTransport() async throws {
        let (client, transport) = try startedClient()

        let task = Task { await client.shutdown() }
        guard let id = transport.awaitRequest() else { return XCTFail("no request was written") }
        XCTAssertEqual(transport.lastSentMethod(), "shutdown")
        transport.emit(line: #"{"id":\#(id),"ok":true,"result":{"stopped":true}}"#)
        await task.value

        XCTAssertEqual(transport.stopCount, 1)
        XCTAssertEqual(client.currentState, .stopped(.stoppedByClient))
    }

    func testWriteFailureFailsThatRequestOnly() async throws {
        let (client, transport) = try startedClient()
        transport.sendError = BridgeError.notRunning

        do {
            _ = try await client.hello()
            XCTFail("expected the write failure to surface")
        } catch let error as BridgeError {
            XCTAssertEqual(error, .notRunning)
        }
    }
}

/// Collects events from the client's callback, which can fire on any thread.
final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CoreEvent] = []

    func append(_ event: CoreEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }

    func all() -> [CoreEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
