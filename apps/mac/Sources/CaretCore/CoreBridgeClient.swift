import Foundation
import os

/// The app's side of the JSON-lines bridge.
///
/// A request carries an `id` and gets one reply with that `id`; evaluation
/// results arrive separately as event lines with no `id`. Both share one pipe,
/// so replies and events interleave and this has to correlate rather than
/// read-after-write.
public final class CoreBridgeClient: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running
        case stopped(CoreTerminationReason)
    }

    /// One outstanding request.
    ///
    /// The id is reserved and this box is installed under the same lock, so a
    /// termination or cancellation that lands before the continuation exists
    /// records its result here instead of finding no slot and leaking the
    /// waiter. All fields are touched only under the client's lock.
    private final class Waiter {
        var continuation: CheckedContinuation<Data, Error>?
        var earlyResult: Result<Data, Error>?
        var settled = false
    }

    private let transport: CoreTransport
    private let log = Logger(subsystem: "com.caret.app", category: "core-bridge")
    private let lock = NSLock()

    private var nextID = 1
    private var pending: [Int: Waiter] = [:]
    private var state: State = .idle
    private var eventSink: ((CoreEvent) -> Void)?

    public init(transport: CoreTransport) {
        self.transport = transport
    }

    public convenience init(configuration: CoreLaunchConfiguration) {
        self.init(transport: CoreProcessTransport(configuration: configuration))
    }

    public var currentState: State {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    /// Install before `start()` so no event between launch and `hello` is lost.
    public func onEvent(_ handler: @escaping (CoreEvent) -> Void) {
        lock.lock()
        eventSink = handler
        lock.unlock()
    }

    public func start() throws {
        lock.lock()
        guard state == .idle else {
            let running = state == .running
            lock.unlock()
            throw running ? BridgeError.alreadyRunning : BridgeError.notRunning
        }
        state = .running
        lock.unlock()

        do {
            try transport.start(
                onLine: { [weak self] line in self?.handle(line: line) },
                onTermination: { [weak self] reason in self?.handleTermination(reason) }
            )
        } catch {
            handleTermination(.failed(String(describing: error)))
            throw error
        }
    }

    /// Asks the core to stop, then tears the transport down regardless of
    /// whether it answered. A child that is wedged must not wedge the app's
    /// quit path, so the reply is waited for only until `timeout`.
    public func shutdown(timeout: TimeInterval = 2) async {
        if currentState == .running {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = try? await self.send(method: "shutdown", params: EmptyParams(), as: StoppedResult.self)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                }
                await group.next()
                group.cancelAll()
                await group.waitForAll()
            }
        }
        transport.stop()
        handleTermination(.stoppedByClient)
    }

    // MARK: - Methods

    public func hello() async throws -> HelloResult {
        try await send(method: "hello", params: EmptyParams(), as: HelloResult.self)
    }

    public func updateContext(_ frame: ContextFrame) async throws -> ContextUpdateResult {
        try await send(method: "context.update", params: FrameParams(frame: frame), as: ContextUpdateResult.self)
    }

    public func accept(proposalID: String, revision: Int, target: TargetIdentity) async throws -> AcceptResult {
        try await send(
            method: "offer.accept",
            params: AcceptParams(proposalID: proposalID, revision: revision, target: target),
            as: AcceptResult.self
        )
    }

    @discardableResult
    public func dismiss(proposalID: String) async throws -> Bool {
        try await send(method: "offer.dismiss", params: DismissParams(proposalID: proposalID), as: DismissResult.self)
            .dismissed
    }

    public func listWorkflows() async throws -> [WorkflowSummary] {
        try await send(method: "workflows.list", params: EmptyParams(), as: WorkflowList.self).workflows
    }

    public func prepareWorkflow(workflowID: String, frame: ContextFrame) async throws -> ActionOffer {
        try await send(
            method: "workflow.prepare",
            params: PrepareParams(workflowID: workflowID, frame: frame),
            as: PrepareResult.self
        ).offer
    }

    // MARK: - Request plumbing

    private struct EmptyParams: Encodable {}
    private struct FrameParams: Encodable { let frame: ContextFrame }
    private struct PrepareParams: Encodable {
        let workflowID: String
        let frame: ContextFrame
        enum CodingKeys: String, CodingKey {
            case workflowID = "workflow_id"
            case frame
        }
    }
    private struct PrepareResult: Decodable { let offer: ActionOffer }
    private struct StoppedResult: Decodable { let stopped: Bool }
    private struct WorkflowList: Decodable { let workflows: [WorkflowSummary] }
    private struct DismissParams: Encodable {
        let proposalID: String
        enum CodingKeys: String, CodingKey { case proposalID = "proposal_id" }
    }
    private struct AcceptParams: Encodable {
        let proposalID: String
        let revision: Int
        let target: TargetIdentity
        enum CodingKeys: String, CodingKey {
            case proposalID = "proposal_id"
            case revision, target
        }
    }
    private struct Envelope<P: Encodable>: Encodable {
        let id: Int
        let method: String
        let params: P
    }

    /// `JSONEncoder` and `JSONDecoder` are not safe to share across threads,
    /// and the reader thread decodes while a caller encodes. Each use gets its
    /// own; at this message rate the allocation does not matter.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    /// Reserves an id and installs its waiter in one step.
    private func reserve() throws -> (id: Int, waiter: Waiter) {
        lock.lock()
        defer { lock.unlock() }
        guard state == .running else {
            switch state {
            case .stopped(.exited(let status)):
                throw BridgeError.processExited(status: status, reason: "core already exited")
            case .stopped(.failed(let detail)):
                throw BridgeError.processExited(status: -1, reason: detail)
            default:
                throw BridgeError.notRunning
            }
        }
        let id = nextID
        nextID += 1
        let waiter = Waiter()
        pending[id] = waiter
        return (id, waiter)
    }

    /// Settles a waiter exactly once, whether or not its continuation exists
    /// yet. Resuming happens outside the lock.
    private func settle(id: Int, waiter: Waiter, with result: Result<Data, Error>) {
        lock.lock()
        if waiter.settled {
            lock.unlock()
            return
        }
        waiter.settled = true
        pending.removeValue(forKey: id)
        let continuation = waiter.continuation
        if continuation == nil { waiter.earlyResult = result }
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func settle(id: Int, with result: Result<Data, Error>) {
        lock.lock()
        let waiter = pending[id]
        lock.unlock()
        guard let waiter else { return }
        settle(id: id, waiter: waiter, with: result)
    }

    func send<P: Encodable, R: Decodable>(method: String, params: P, as: R.Type) async throws -> R {
        let (id, waiter) = try reserve()

        let line = String(
            data: try Self.makeEncoder().encode(Envelope(id: id, method: method, params: params)),
            encoding: .utf8
        )
        guard let line else {
            settle(id: id, waiter: waiter, with: .failure(BridgeError.malformedReply("request was not UTF-8")))
            throw BridgeError.malformedReply("request was not encodable as UTF-8")
        }

        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let early = waiter.earlyResult {
                    // Cancelled or the core exited between reserve() and here.
                    lock.unlock()
                    continuation.resume(with: early)
                    return
                }
                waiter.continuation = continuation
                lock.unlock()

                do {
                    try transport.send(line: line)
                } catch {
                    settle(id: id, waiter: waiter, with: .failure(error))
                }
            }
        } onCancel: {
            // The core has no cancel verb; a late reply is dropped by id.
            settle(id: id, waiter: waiter, with: .failure(BridgeError.cancelled))
        }

        do {
            let reply = try JSONDecoder().decode(Reply<R>.self, from: data)
            if reply.ok, let result = reply.result { return result }
            if let error = reply.error { throw BridgeError.core(code: error.code, message: error.message) }
            throw BridgeError.malformedReply("reply for '\(method)' carried neither result nor error")
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.malformedReply("could not decode the reply to '\(method)'")
        }
    }

    private struct Reply<R: Decodable>: Decodable {
        let id: Int?
        let ok: Bool
        let result: R?
        let error: CoreErrorPayload?
    }

    // MARK: - Line handling

    private struct LineHeader: Decodable {
        let id: Int?
        let event: String?
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        guard let header = try? JSONDecoder().decode(LineHeader.self, from: data) else {
            log.error("core sent a line with neither 'id' nor 'event'")
            return
        }
        if let id = header.id {
            settle(id: id, with: .success(data))
            return
        }
        guard let name = header.event else {
            log.error("core reported a failure with no request id")
            return
        }
        deliver(event: decodeEvent(named: name, from: data))
    }

    private struct EventLine: Decodable {
        let offer: Offer?
        let revision: Int?
        let reason: String?
        let proposalID: String?
        enum CodingKeys: String, CodingKey {
            case offer, revision, reason
            case proposalID = "proposal_id"
        }
    }

    private func decodeEvent(named name: String, from data: Data) -> CoreEvent {
        let line = try? JSONDecoder().decode(EventLine.self, from: data)
        let reason = line?.reason ?? ""
        let revision = line?.revision ?? -1
        switch name {
        case "offer":
            if let offer = line?.offer { return .offer(offer) }
            return .unknown(name: "offer(undecodable)")
        case "abstain": return .abstain(revision: revision, reason: reason)
        case "invalidated": return .invalidated(proposalID: line?.proposalID ?? "", reason: reason)
        case "discarded": return .discarded(revision: revision, reason: reason)
        case "failed": return .failed(revision: revision, reason: reason)
        default: return .unknown(name: name)
        }
    }

    private func deliver(event: CoreEvent) {
        lock.lock()
        let sink = eventSink
        lock.unlock()
        sink?(event)
    }

    private func handleTermination(_ reason: CoreTerminationReason) {
        lock.lock()
        if case .stopped = state {
            lock.unlock()
            return
        }
        state = .stopped(reason)
        let waiters = pending
        lock.unlock()

        let failure: BridgeError
        switch reason {
        case .exited(let status): failure = .processExited(status: status, reason: "core stdout reached EOF")
        case .stoppedByClient: failure = .notRunning
        case .failed(let detail): failure = .processExited(status: -1, reason: detail)
        }
        // The transport drains stdout before calling us, so a reply already on
        // the wire has been delivered and its waiter is gone by now.
        for (id, waiter) in waiters { settle(id: id, waiter: waiter, with: .failure(failure)) }
    }
}
