import Foundation

struct JPEGFrameBuffer {
    struct InvalidFrame: LocalizedError {
        var errorDescription: String? { "Некорректный видеопоток с Repka" }
    }

    private static let maxFrameBytes = 4 * 1024 * 1024
    private let expectedLength: Int?
    private var bytes = Data()

    init(expectedLength: Int64) throws {
        if expectedLength < 0 {
            self.expectedLength = nil
        } else if (1...Int64(Self.maxFrameBytes)).contains(expectedLength) {
            self.expectedLength = Int(expectedLength)
        } else {
            throw InvalidFrame()
        }
    }

    mutating func append(_ data: Data) throws -> Data? {
        guard data.count <= (expectedLength ?? Self.maxFrameBytes) - bytes.count else { throw InvalidFrame() }
        bytes.append(data)
        return bytes.count == expectedLength ? bytes : nil
    }

    func finish() throws -> Data {
        guard !bytes.isEmpty, expectedLength == nil || expectedLength == bytes.count else { throw InvalidFrame() }
        return bytes
    }
}
