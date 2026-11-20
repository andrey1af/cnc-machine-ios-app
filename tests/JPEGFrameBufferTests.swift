import Foundation
import XCTest
@testable import CNCCore

final class JPEGFrameBufferTests: XCTestCase {
    func testFrameIsReadyAsSoonAsAllBytesArrive() throws {
        var frame = try JPEGFrameBuffer(expectedLength: 5)
        XCTAssertNil(try frame.append(Data([0xFF, 0xD8])))
        XCTAssertEqual(try frame.append(Data([0x12, 0xFF, 0xD9])), Data([0xFF, 0xD8, 0x12, 0xFF, 0xD9]))
    }

    func testFrameWithoutLengthIsReadyWhenPartEnds() throws {
        var frame = try JPEGFrameBuffer(expectedLength: -1)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        XCTAssertNil(try frame.append(bytes))
        XCTAssertEqual(try frame.finish(), bytes)
    }

    func testRejectsOversizedAndTruncatedFrames() throws {
        XCTAssertThrowsError(try JPEGFrameBuffer(expectedLength: 4_194_305))
        var frame = try JPEGFrameBuffer(expectedLength: 2)
        XCTAssertThrowsError(try frame.append(Data([1, 2, 3])))
        XCTAssertNil(try frame.append(Data([1])))
        XCTAssertThrowsError(try frame.finish())
    }
}
