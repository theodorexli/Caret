import Darwin
import Foundation
import os

/// Where the core lives and which interpreter runs it.
///
/// Nothing here is baked in. The launch root and the Python executable are both
/// supplied by the caller, because this is a developer's local app and the
/// repository is wherever that developer put it. `--judge scripted:` is
/// deliberately absent: the core refuses to fall back to a canned response, and
/// the app must not hand it one either, so an unconfigured machine fails
/// visibly instead of producing output that looks like a model result.
public struct CoreLaunchConfiguration: Equatable, Sendable {
    /// Directory the core is run from; `-m caret.bridge` resolves against it.
    public var rootURL: URL
    /// Interpreter to run. Resolved by the caller (a settings value, a
    /// `PATH` lookup, or a virtualenv) rather than guessed here.
    public var pythonURL: URL
    public var moduleName: String
    /// Extra flags such as `--fixture`, `--db`, `--judge`, `--writer`.
    public var arguments: [String]
    /// Added to the child's environment. Provider keys (`TYPESAFE_API_KEY`,
    /// `GROQ_API_KEY`) belong here, read from the user's own environment or
    /// Keychain by the caller. They are never logged.
    public var environmentOverrides: [String: String]

    public init(
        rootURL: URL,
        pythonURL: URL,
        moduleName: String = "caret.bridge",
        arguments: [String] = [],
        environmentOverrides: [String: String] = [:]
    ) {
        self.rootURL = rootURL
        self.pythonURL = pythonURL
        self.moduleName = moduleName
        self.arguments = arguments
        self.environmentOverrides = environmentOverrides
    }
}

/// Runs the core as a long-lived child process and moves whole lines over its
/// stdin and stdout.
///
/// One dedicated reader thread owns stdout from first byte to termination. It
/// reads, delivers every line, and only then reports the exit. That ordering is
/// structural rather than coordinated: there is no second reader to race, so a
/// reply sitting in the pipe when the child exits cannot be lost behind the
/// termination that follows it. The main thread never blocks on the pipe.
public final class CoreProcessTransport: CoreTransport {
    /// A dead child closes its read end of stdin; a late write then raises
    /// SIGPIPE and kills the host unless it is ignored (common for pipe writers).
    private static let ignoreSIGPIPE: Void = {
        _ = signal(SIGPIPE, SIG_IGN)
    }()

    private let configuration: CoreLaunchConfiguration
    private let log = Logger(subsystem: "com.caret.app", category: "core-transport")
    private let lock = NSLock()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdinClosed = false
    private var terminated = false
    private var stderrLineCount = 0

    public init(configuration: CoreLaunchConfiguration) {
        Self.ignoreSIGPIPE
        self.configuration = configuration
    }

    public func start(
        onLine: @escaping (String) -> Void,
        onTermination: @escaping (CoreTerminationReason) -> Void
    ) throws {
        lock.lock()
        guard process == nil else {
            lock.unlock()
            throw BridgeError.alreadyRunning
        }
        lock.unlock()

        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = configuration.pythonURL
        process.currentDirectoryURL = configuration.rootURL
        process.arguments = ["-u", "-m", configuration.moduleName] + configuration.arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environmentOverrides { environment[key] = value }
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Lifecycle state is stored before run(). A child that exits instantly
        // would otherwise reach the exit path while these were still nil.
        lock.lock()
        self.process = process
        self.stdinPipe = stdin
        self.terminated = false
        self.stdinClosed = false
        self.stderrLineCount = 0
        lock.unlock()

        // A provider failure can echo upstream response text, which may contain
        // whatever the user was typing. stderr is counted, never logged and
        // never placed in a termination reason.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.countStderr(chunk)
        }

        do {
            try process.run()
        } catch {
            lock.lock()
            self.process = nil
            self.stdinPipe = nil
            lock.unlock()
            stderr.fileHandleForReading.readabilityHandler = nil
            throw BridgeError.launchFailed(error.localizedDescription)
        }

        let reader = Thread { [weak self] in
            self?.readUntilEOF(
                handle: stdout.fileHandleForReading,
                process: process,
                onLine: onLine,
                onTermination: onTermination
            )
        }
        reader.name = "caret.core-transport.reader"
        reader.stackSize = 512 * 1024
        reader.start()

        log.info("core process started")
    }

    public func send(line: String) throws {
        lock.lock()
        let pipe = stdinPipe
        let running = process?.isRunning ?? false
        let stdinClosed = self.stdinClosed
        lock.unlock()
        guard let pipe, running, !stdinClosed else { throw BridgeError.notRunning }
        guard let data = (line + "\n").data(using: .utf8) else {
            throw BridgeError.malformedReply("request was not encodable as UTF-8")
        }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw BridgeError.notRunning
        }
    }

    public func stop() {
        lock.lock()
        let process = self.process
        let stdin = self.stdinPipe
        lock.unlock()
        // Closing stdin is how the core is asked to leave: its read loop ends,
        // it exits, stdout reaches EOF and the reader thread finishes.
        lock.lock()
        stdinClosed = true
        lock.unlock()
        try? stdin?.fileHandleForWriting.close()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    // MARK: - Reader

    /// Owns stdout for the life of the process. `availableData` blocks until
    /// bytes arrive or the write end closes, so the loop ends exactly at EOF.
    private func readUntilEOF(
        handle: FileHandle,
        process: Process,
        onLine: @escaping (String) -> Void,
        onTermination: @escaping (CoreTerminationReason) -> Void
    ) {
        var accumulator = LineAccumulator()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            for line in accumulator.append(chunk) { onLine(line) }
        }
        // Anything the child wrote without a closing newline.
        if let trailing = accumulator.flush() { onLine(trailing) }

        // Every line is delivered before the exit is reported.
        process.waitUntilExit()
        finish(reason: .exited(status: process.terminationStatus), onTermination: onTermination)
    }

    private func countStderr(_ chunk: Data) {
        let count = chunk.reduce(into: 0) { total, byte in
            if byte == UInt8(ascii: "\n") { total += 1 }
        }
        lock.lock()
        stderrLineCount += max(count, 1)
        lock.unlock()
    }

    private func finish(reason: CoreTerminationReason, onTermination: @escaping (CoreTerminationReason) -> Void) {
        lock.lock()
        if terminated {
            lock.unlock()
            return
        }
        terminated = true
        let suppressed = stderrLineCount
        lock.unlock()

        if suppressed > 0 {
            // The count is safe to record; the text is not.
            log.error("core wrote \(suppressed, privacy: .public) diagnostic line(s) before exiting")
        }
        onTermination(reason)
    }
}
