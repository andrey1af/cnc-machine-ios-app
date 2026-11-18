import Foundation

enum Axis: String, CaseIterable, Codable, Sendable {
    case x = "X"
    case y = "Y"
    case z = "Z"
}

struct MachineStatus: Codable, Equatable, Sendable {
    var connected: Bool
    var state: String
    var pos: [Double]
    var posLabel: String
    var pins: String
    var step: Double
    var feedXY: Double
    var feedZ: Double
    var maxFeedXY: Double
    var maxFeedZ: Double
    var program: ProgramStatus
    var lastRun: ProgramStatus?

    static let disconnected = MachineStatus(
        connected: false,
        state: "—",
        pos: [0, 0, 0],
        posLabel: "",
        pins: "",
        step: 1,
        feedXY: 100,
        feedZ: 300,
        maxFeedXY: 300,
        maxFeedZ: 300,
        program: .empty,
        lastRun: nil
    )

    func position(for axis: Axis) -> Double {
        let index: Int
        switch axis {
        case .x: index = 0
        case .y: index = 1
        case .z: index = 2
        }
        return pos.indices.contains(index) ? pos[index] : 0
    }

    var isAlarm: Bool { state.localizedCaseInsensitiveContains("alarm") }
    var isIdle: Bool { state == "Idle" }
    var isOnHold: Bool { state.hasPrefix("Hold") }
}

struct ProgramStatus: Codable, Equatable, Sendable {
    var revision: UInt64? = nil
    var currentLine: Int? = nil
    var currentText: String? = nil
    var completed: Int? = nil
    var elapsedSeconds: Int? = nil
    var remainingSeconds: Int? = nil
    var id: UInt64
    var name: String
    var lines: Int
    var sent: Int
    var running: Bool
    var state: String
    var lastLine: Int
    var error: String?
    var startedAt: String?
    var finishedAt: String?

    static let empty = ProgramStatus(
        id: 0,
        name: "",
        lines: 0,
        sent: 0,
        running: false,
        state: "",
        lastLine: 0,
        error: nil,
        startedAt: nil,
        finishedAt: nil
    )

    var progress: Double {
        guard lines > 0 else { return 0 }
        return min(max(Double(sent) / Double(lines), 0), 1)
    }

    static func duration(_ seconds: Int, roundUp: Bool = false) -> String {
        let positive = max(0, seconds)
        let minutes = roundUp ? (positive + 59) / 60 : positive / 60
        return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
    }

    var statusText: String {
        guard !name.isEmpty else { return "Программа не загружена" }
        switch state {
        case "queued": return "Ожидает запуска"
        case "running": return "Отправлено \(sent) из \(lines) строк"
        case "completed": return "Выполнена"
        case "canceled": return "Отменена на строке \(lastLine)"
        case "failed": return "Ошибка в строке \(lastLine)"
        default: return "\(lines) строк"
        }
    }
}

struct LogEntry: Codable, Identifiable, Equatable, Sendable {
    let id: Int64
    let time: String
    let level: String
    let msg: String
    let attrs: String?

    var timestamp: String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: time)
                ?? ISO8601DateFormatter().date(from: time) else {
            return time
        }
        return DateFormatter.logTime.string(from: date)
    }
}

struct HelloEvent: Codable, Sendable {
    let boot: Int64
}

struct ProgramResponse: Codable, Sendable {
    let name: String
    let lines: Int
}

struct ErrorResponse: Codable, Sendable {
    let message: String
    let details: String?
}

enum ServerConnection: Equatable {
    case connecting
    case serverOffline
    case controllerOffline
    case connected

    var title: String {
        switch self {
        case .connecting: return "Подключение…"
        case .serverOffline: return "Сервер недоступен"
        case .controllerOffline: return "Контроллер отключён"
        case .connected: return "Подключено"
        }
    }

    var symbol: String {
        switch self {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .serverOffline: return "wifi.slash"
        case .controllerOffline: return "cable.connector.slash"
        case .connected: return "checkmark.circle.fill"
        }
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

struct ToolpathPreview: Codable, Sendable {
    let revision: UInt64
    let segments: [ToolpathSegment]
    let warning: String
}
struct ToolpathSegment: Codable, Sendable {
    let line: Int
    let command: Int
    let text: String
    let rapid: Bool
    let points: [[Double]]
}
