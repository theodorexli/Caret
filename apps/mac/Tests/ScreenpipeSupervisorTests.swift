import Darwin
import XCTest

final class ScreenpipeSupervisorTests: XCTestCase {
    func testLeaseURLAndPinEndpoint() throws {
        let root = URL(fileURLWithPath: "/tmp/caret-root")
        XCTAssertEqual(
            ScreenpipeSupervisor.leaseURL(projectRoot: root).path,
            "/tmp/caret-root/.local/screenpipe-lease.json"
        )
        let data = try JSONSerialization.data(
            withJSONObject: [
                "artifact_id": "screenpipe-npm-0.4.50",
                "expected_health_version": "0.4.50",
                "launch": ["npx", "--disable-clipboard-capture", "false", "--port", "3031"],
            ]
        )
        let pin = try ScreenpipeSupervisor.loadPin(data: data)
        XCTAssertEqual(ScreenpipeSupervisor.endpoint(from: pin["launch"] as! [String]), "http://127.0.0.1:3031")
        let lease = ScreenpipeSupervisor.leasePayload(
            pin: pin,
            checksum: "abc",
            endpoint: "http://127.0.0.1:3031",
            pid: 9,
            readyAt: "t"
        )
        XCTAssertEqual(lease["artifact_id"] as? String, "screenpipe-npm-0.4.50")
        XCTAssertEqual(lease["pid"] as? Int, 9)
        XCTAssertEqual(lease["endpoint"] as? String, "http://127.0.0.1:3031")
    }

    func testPortFromLaunchArgs() {
        XCTAssertEqual(
            ScreenpipeSupervisor.port(from: ["npx", "--port", "3031"]),
            3031
        )
        XCTAssertEqual(ScreenpipeSupervisor.port(from: ["npx"]), 3030)
    }

    func testIsListeningFalseWhenPortFree() throws {
        let listener = try LocalTCPListener()
        let port = listener.port
        listener.stop()
        XCTAssertFalse(ScreenpipeSupervisor.isListening(port: port))
    }

    func testIsListeningTrueWhenPortBound() throws {
        let listener = try LocalTCPListener()
        defer { listener.stop() }
        XCTAssertTrue(ScreenpipeSupervisor.isListening(port: listener.port))
    }

    func testShouldSpawnOnlyWhenPortFree() throws {
        let listener = try LocalTCPListener()
        defer { listener.stop() }
        XCTAssertFalse(ScreenpipeSupervisor.shouldSpawn(port: listener.port))
        listener.stop()
        XCTAssertTrue(ScreenpipeSupervisor.shouldSpawn(port: listener.port))
    }

    func testAdoptedHealthyListenerWritesLeaseWithSentinelPid() throws {
        let stub = try LocalHealthStub(version: "0.4.50")
        defer { stub.stop() }
        let root = try writeTempPin(port: stub.port)
        defer { try? FileManager.default.removeItem(at: root) }

        let leaseURL = try ScreenpipeSupervisor.run(projectRoot: root)
        let lease = try leaseJSON(at: leaseURL)
        XCTAssertEqual(lease["pid"] as? Int, 0)
        XCTAssertEqual(lease["endpoint"] as? String, "http://127.0.0.1:\(stub.port)")

        ScreenpipeSupervisor.stop()
        XCTAssertTrue(ScreenpipeSupervisor.isListening(port: stub.port))
    }

    func testRunReplacesStaleLeaseWhenAdopting() throws {
        let stub = try LocalHealthStub(version: "0.4.50")
        defer { stub.stop() }
        let root = try writeTempPin(port: stub.port)
        defer { try? FileManager.default.removeItem(at: root) }

        let leaseURL = ScreenpipeSupervisor.leaseURL(projectRoot: root)
        try FileManager.default.createDirectory(at: leaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["checksum": "stale"]).write(to: leaseURL)

        let written = try ScreenpipeSupervisor.run(projectRoot: root)
        let lease = try leaseJSON(at: written)
        XCTAssertNotEqual(lease["checksum"] as? String, "stale")
        XCTAssertEqual(lease["pid"] as? Int, 0)
        ScreenpipeSupervisor.stop()
    }
}

private func writeTempPin(port: Int) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let caret = root.appendingPathComponent("caret", isDirectory: true)
    try FileManager.default.createDirectory(at: caret, withIntermediateDirectories: true)
    let pin: [String: Any] = [
        "artifact_id": "screenpipe-npm-0.4.50",
        "expected_health_version": "0.4.50",
        "launch": ["/usr/bin/true", "--disable-clipboard-capture", "false", "--port", "\(port)"],
    ]
    try JSONSerialization.data(withJSONObject: pin).write(to: caret.appendingPathComponent("screenpipe_pin.json"))
    return root
}

private func leaseJSON(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "ScreenpipeSupervisorTests", code: 1)
    }
    return json
}

/// Listen on 127.0.0.1 with an ephemeral port. Used to occupy a port without HTTP.
private final class LocalTCPListener {
    let port: Int
    private let fd: Int32

    init() throws {
        let bound = try bindLocal(http: false)
        fd = bound.fd
        port = bound.port
    }

    func stop() {
        Darwin.close(fd)
    }
}

/// Serve `{"status":"ok","version":...}` on GET /health at 127.0.0.1.
private final class LocalHealthStub {
    let port: Int
    private let fd: Int32
    private let queue = DispatchQueue(label: "caret.health-stub")

    init(version: String) throws {
        let bound = try bindLocal(http: true)
        fd = bound.fd
        port = bound.port
        let body = "{\"status\":\"ok\",\"version\":\"\(version)\"}"
        let response =
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let payload = Array(response.utf8)
        let listenFD = fd
        queue.async {
            while true {
                let client = Darwin.accept(listenFD, nil, nil)
                if client < 0 { break }
                var discard = [UInt8](repeating: 0, count: 1024)
                _ = Darwin.recv(client, &discard, discard.count, 0)
                _ = payload.withUnsafeBytes { Darwin.send(client, $0.baseAddress, payload.count, 0) }
                Darwin.close(client)
            }
        }
    }

    func stop() {
        Darwin.close(fd)
    }
}

private func bindLocal(http: Bool) throws -> (fd: Int32, port: Int) {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO) }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    addr.sin_port = 0
    let bindOK = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
    guard bindOK, Darwin.listen(fd, 8) == 0 else {
        Darwin.close(fd)
        throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO)
    }
    var actual = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameOK = withUnsafeMutablePointer(to: &actual) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(fd, $0, &len) == 0
        }
    }
    guard nameOK else {
        Darwin.close(fd)
        throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO)
    }
    _ = http
    return (fd, Int(UInt16(bigEndian: actual.sin_port)))
}
