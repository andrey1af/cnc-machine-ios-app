import Foundation
import XCTest
@testable import CNCCore

final class ServerPayloadTests: XCTestCase {
    func testStatusDecodesWorkCoordinatesAndProgramEstimate() throws {
        let json = """
        {
          "connected": true, "state": "Run", "pos": [12.25, -4.5, 0], "posLabel": "WPos",
          "pins": "", "step": 1, "feedXY": 100, "feedZ": 50, "maxFeedXY": 300, "maxFeedZ": 300,
          "program": {
            "id": 2, "name": "preview.gcode", "lines": 8, "sent": 4,
            "running": true, "state": "running", "lastLine": 4, "revision": 3,
            "currentLine": 3, "completed": 2, "elapsedSeconds": 60, "remainingSeconds": 180
          }
        }
        """
        var status = try JSONDecoder().decode(MachineStatus.self, from: Data(json.utf8))

        XCTAssertTrue(status.hasPosition)
        XCTAssertEqual(Axis.allCases.map { status.coordinateText(for: $0) }, ["+12.250", "-4.500", "+0.000"])
        XCTAssertEqual(status.program.revision, 3)
        XCTAssertEqual(status.program.progress, 0.5)
        XCTAssertEqual(status.program.remainingSeconds, 180)
        XCTAssertFalse(status.canStartProgram)

        status.connected = false
        XCTAssertFalse(status.hasPosition)
        XCTAssertEqual(status.coordinateText(for: .x), "—")
    }

    func testStatusAcceptsProgramWithoutOptionalPreviewAndEstimateFields() throws {
        let json = """
        {
          "id": 0, "name": "preview.gcode", "lines": 8, "sent": 0,
          "running": false, "state": "loaded", "lastLine": 0
        }
        """
        let program = try JSONDecoder().decode(ProgramStatus.self, from: Data(json.utf8))

        XCTAssertEqual(program.statusText, "8 строк")
        XCTAssertNil(program.revision)
        XCTAssertNil(program.remainingSeconds)
    }

    func testInvalidPositionDoesNotDisplayAsZero() {
        var status = MachineStatus.disconnected
        status.connected = true
        status.posLabel = "MPos"
        status.pos = [1, 2, 3]
        XCTAssertEqual(status.coordinateText(for: .z), "+3.000")

        status.pos = [1, 2]
        XCTAssertFalse(status.hasPosition)
        XCTAssertEqual(status.coordinateText(for: .z), "—")

        status.pos = [1, .infinity, 3]
        XCTAssertFalse(status.hasPosition)
        XCTAssertEqual(status.coordinateText(for: .y), "—")
    }
}
