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
}
