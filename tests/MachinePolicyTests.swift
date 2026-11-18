import XCTest
@testable import CNCCore

final class MachinePolicyTests: XCTestCase {
    func testUploadBlockedUntilServerResponds() {
        let status = MachineStatus.disconnected

        XCTAssertFalse(status.canUploadProgram(connection: .connecting, isUploading: false))
        XCTAssertFalse(status.canUploadProgram(connection: .serverOffline, isUploading: false))
        XCTAssertTrue(status.canUploadProgram(connection: .controllerOffline, isUploading: false))
        XCTAssertTrue(status.canUploadProgram(connection: .connected, isUploading: false))
    }

    func testUploadBlockedDuringExecutionOrUpload() {
        var status = MachineStatus.disconnected
        XCTAssertFalse(status.canUploadProgram(connection: .connected, isUploading: true))

        status.program.running = true
        XCTAssertFalse(status.canUploadProgram(connection: .connected, isUploading: false))
    }

    func testStartRequiresControllerAndLoadedInactiveProgram() {
        var status = MachineStatus.disconnected
        status.program.name = "preview.gcode"
        XCTAssertFalse(status.canStartProgram)

        status.connected = true
        XCTAssertTrue(status.canStartProgram)

        status.program.running = true
        XCTAssertFalse(status.canStartProgram)

        status.program = .empty
        XCTAssertFalse(status.canStartProgram)
    }

    func testFirstFailureNeedsManualConnection() {
        var policy = ReconnectPolicy()
        XCTAssertFalse(policy.consumeRetry())
    }

    func testDisconnectAfterStatusGetsThreeRetries() {
        var policy = ReconnectPolicy()
        policy.recordServerStatus()

        XCTAssertEqual(ReconnectPolicy.retryDelay, .seconds(5))
        XCTAssertEqual((1...4).map { _ in policy.consumeRetry() }, [true, true, true, false])

        policy.recordServerStatus()
        XCTAssertEqual((1...4).map { _ in policy.consumeRetry() }, [true, true, true, false])
    }

    func testManualConnectionClearsPendingRetryBudget() {
        var policy = ReconnectPolicy()
        policy.recordServerStatus()
        XCTAssertTrue(policy.consumeRetry())

        policy.reset()
        XCTAssertFalse(policy.consumeRetry())
    }
}
