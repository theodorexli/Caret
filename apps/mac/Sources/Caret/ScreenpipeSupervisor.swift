import CryptoKit
import Darwin
import Foundation

enum ScreenpipeSupervisorError: Error {
    case invalidPin
    case notHealthy
}

enum ScreenpipeSupervisor {
    static let launchdLabel = "dev.caret.hackathon.screenpipe"
    static var ownsJob = false
    static var healthWaitSeconds: TimeInterval = 60
    static var resolveBinaryHandler: (([String: Any]) throws -> URL)?
    static var bootstrapHandler: ((URL) throws -> Void)?
    static var bootoutHandler: (() throws -> Void)?

    static func resetTestState() {
        ownsJob = false
        healthWaitSeconds = 60
        resolveBinaryHandler = nil
        bootstrapHandler = nil
        bootoutHandler = nil
    }

    /// `launch[0]` is the binary name; argv starts with the resolved Mach-O.
    static func programArguments(binary: URL, launch: [String]) -> [String] {
        [binary.path] + Array(launch.dropFirst())
    }

    static func launchdPlistURL(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".local/\(launchdLabel).plist")
    }

    static func launchdPlist(
        label: String,
        arguments: [String],
        workingDirectory: String,
        standardOut: String,
        standardError: String
    ) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": arguments,
            "WorkingDirectory": workingDirectory,
            "StandardOutPath": standardOut,
            "StandardErrorPath": standardError,
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
    }

    static func resolveBinary(pin: [String: Any]) throws -> URL {
        if let resolveBinaryHandler {
            return try resolveBinaryHandler(pin)
        }
        let package = pin["package"] as? String ?? "screenpipe"
        let version = pin["version"] as? String
            ?? pin["expected_health_version"] as? String
            ?? "0.4.50"
        let name = (pin["launch"] as? [String])?.first ?? "screenpipe"
        let output = try runCommand(
            "/usr/bin/env",
            ["npx", "-y", "--package", "\(package)@\(version)", "which", name]
        )
        let path = output.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { throw ScreenpipeSupervisorError.invalidPin }
        return try nativeBinary(fromShim: URL(fileURLWithPath: path))
    }

    /// npm `which` is a node shim. TCC must see the Developer ID Mach-O.
    static func nativeBinary(fromShim shim: URL) throws -> URL {
        let nodeModules = shim.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for triple in ["cli-darwin-arm64", "cli-darwin-x64"] {
            let candidate = nodeModules
                .appendingPathComponent("@screenpipe")
                .appendingPathComponent(triple)
                .appendingPathComponent("bin")
                .appendingPathComponent("screenpipe")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw ScreenpipeSupervisorError.invalidPin
    }

    static func pinURL(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent("caret/screenpipe_pin.json")
    }

    static func leaseURL(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".local/screenpipe-lease.json")
    }

    static func loadPin(data: Data) throws -> [String: Any] {
        guard let pin = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let launch = pin["launch"] as? [String],
              launch.contains("--disable-clipboard-capture")
        else { throw ScreenpipeSupervisorError.invalidPin }
        return pin
    }

    static func endpoint(from launch: [String]) -> String {
        "http://127.0.0.1:\(port(from: launch))"
    }

    /// Pin `--port` value, or Screenpipe's historical default.
    static func port(from launch: [String]) -> Int {
        if let index = launch.firstIndex(of: "--port"),
           launch.indices.contains(index + 1),
           let value = Int(launch[index + 1])
        {
            return value
        }
        return 3030
    }

    /// True when something accepts a TCP connection on 127.0.0.1:`port`.
    static func isListening(port: Int) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        addr.sin_port = in_port_t(UInt16(clamping: port)).bigEndian
        return withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Launch the pin only when the expected port has no listener.
    static func shouldSpawn(port: Int) -> Bool {
        !isListening(port: port)
    }

    static func leasePayload(
        pin: [String: Any],
        checksum: String,
        endpoint: String,
        pid: Int,
        readyAt: String
    ) -> [String: Any] {
        [
            "artifact_id": pin["artifact_id"] as? String ?? "",
            "checksum": checksum,
            "expected_version": pin["expected_health_version"] as? String ?? "",
            "endpoint": endpoint,
            "pid": pid,
            "ready_at": readyAt,
        ]
    }

    static func start(projectRoot: URL?) {
        guard let projectRoot else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = try? run(projectRoot: projectRoot)
        }
    }

    static func stop() {
        if ownsJob {
            if let bootoutHandler {
                try? bootoutHandler()
            } else {
                _ = try? launchctl(["bootout", "gui/\(getuid())/\(launchdLabel)"])
            }
            ownsJob = false
        }
    }

    @discardableResult
    static func run(projectRoot: URL) throws -> URL {
        let data = try Data(contentsOf: pinURL(projectRoot: projectRoot))
        let pin = try loadPin(data: data)
        guard let launch = pin["launch"] as? [String], !launch.isEmpty else {
            throw ScreenpipeSupervisorError.invalidPin
        }
        let lease = leaseURL(projectRoot: projectRoot)
        try? FileManager.default.removeItem(at: lease)
        let expectedPort = port(from: launch)
        var pid = 0
        if shouldSpawn(port: expectedPort) {
            let binary = try resolveBinary(pin: pin)
            let arguments = programArguments(binary: binary, launch: launch)
            let local = projectRoot.appendingPathComponent(".local", isDirectory: true)
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            let plistURL = launchdPlistURL(projectRoot: projectRoot)
            let plist = launchdPlist(
                label: launchdLabel,
                arguments: arguments,
                workingDirectory: projectRoot.path,
                standardOut: local.appendingPathComponent("screenpipe.out.log").path,
                standardError: local.appendingPathComponent("screenpipe.err.log").path
            )
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: plistURL)
            ownsJob = true
            if let bootstrapHandler {
                try bootstrapHandler(plistURL)
            } else {
                try bootstrapLaunchd(plistURL: plistURL)
            }
        }
        let endpoint = endpoint(from: launch)
        try waitForHealth(endpoint: endpoint, version: pin["expected_health_version"] as? String ?? "")
        if ownsJob {
            pid = jobPID() ?? 1
        }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let payload = leasePayload(
            pin: pin,
            checksum: checksum,
            endpoint: endpoint,
            pid: pid,
            readyAt: ISO8601DateFormatter().string(from: Date())
        )
        try FileManager.default.createDirectory(at: lease.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: lease)
        return lease
    }

    private static func bootstrapLaunchd(plistURL: URL) throws {
        let domain = "gui/\(getuid())"
        _ = try? launchctl(["bootout", "\(domain)/\(launchdLabel)"])
        try launchctl(["bootstrap", domain, plistURL.path])
    }

    private static func jobPID() -> Int? {
        guard let printed = try? launchctl(["print", "gui/\(getuid())/\(launchdLabel)"]) else {
            return nil
        }
        for line in printed.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid = "), let value = Int(trimmed.dropFirst(6)) {
                return value
            }
        }
        return nil
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) throws -> String {
        try runCommand("/bin/launchctl", arguments)
    }

    @discardableResult
    private static func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ScreenpipeSupervisorError.notHealthy
        }
        return output
    }

    private static func waitForHealth(endpoint: String, version: String) throws {
        let deadline = Date().addingTimeInterval(healthWaitSeconds)
        while Date() < deadline {
            if let url = URL(string: endpoint + "/health"),
               let data = try? Data(contentsOf: url),
               let health = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               health["version"] as? String == version
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ScreenpipeSupervisorError.notHealthy
    }
}
