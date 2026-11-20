import Foundation
import XCTest
@testable import CNCCore

final class ServerPayloadTests: XCTestCase {
    func testControllerSettingsUseBoardValuesAndKeepOnlyEditsWithUnchangedOriginals() throws {
        func settings(feed: Int, delay: Int) throws -> [ControllerSettingGroup] {
            let payload = """
            [{"title":"Оси", "settings":[
              {"id":"110", "label":"Скорость X", "unit":"мм/мин", "kind":"decimal", "min":1, "max":100000, "value":\(feed)},
              {"id":"1", "label":"Задержка", "kind":"integer", "min":0, "max":255, "value":\(delay)},
              {"id":"21", "label":"Концевики", "kind":"toggle", "min":0, "max":1, "value":1},
              {"id":"28", "label":"Частота ШИМ", "kind":"decimal", "min":0, "max":100000, "value":null}
            ]}]
            """
            return try JSONDecoder().decode([ControllerSettingGroup].self, from: Data(payload.utf8))
        }

        var draft = ControllerSettingsDraft()
        draft.replace(with: try settings(feed: 500, delay: 25))
        XCTAssertEqual(draft.values, ["110": "500", "1": "25", "21": "1"])
        XCTAssertTrue(draft.edited.isEmpty)

        draft.values["110"] = "450,5"
        draft.values["1"] = "30"
        XCTAssertEqual(draft.edited.map(\.id), ["110", "1"])
        XCTAssertEqual(draft.edited.first?.parse("450,5"), 450.5)
        XCTAssertNil(draft.edited.last?.parse("30,5"))
        XCTAssertNil(draft.edited.last?.parse("256"))

        draft.replace(with: try settings(feed: 480, delay: 25), keepingEdits: true)
        XCTAssertEqual(draft.values, ["110": "480", "1": "30", "21": "1"])
        XCTAssertEqual(draft.edited.map(\.id), ["1"])
    }

    func testControllerSettingChangeEncodesExpectedAndConfirmedValues() throws {
        let data = try JSONEncoder().encode(["110": ControllerSettingChange(from: 500, to: 450.5)])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Double]])
        XCTAssertEqual(payload, ["110": ["from": 500, "to": 450.5]])
    }

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
