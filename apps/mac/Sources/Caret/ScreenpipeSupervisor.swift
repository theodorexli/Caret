import CryptoKit
import Darwin
import Foundation

enum ScreenpipeSupervisorError: Error {
    case invalidPin
    case notHealthy
}

enum ScreenpipeSupervisor {
    private static var process: Process?

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
        process?.terminate()
        process = nil
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
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            child.arguments = launch
            child.currentDirectoryURL = projectRoot
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
            child.environment = environment
            try child.run()
            process = child
            pid = Int(child.processIdentifier)
        }
        let endpoint = endpoint(from: launch)
        try waitForHealth(endpoint: endpoint, version: pin["expected_health_version"] as? String ?? "")
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

    private static func waitForHealth(endpoint: String, version: String) throws {
        let deadline = Date().addingTimeInterval(60)
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
