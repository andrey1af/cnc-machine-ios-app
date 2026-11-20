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

    var hasPosition: Bool {
        connected && (posLabel == "WPos" || posLabel == "MPos") &&
        pos.count == Axis.allCases.count && pos.allSatisfy(\.isFinite)
    }

    func coordinateText(for axis: Axis) -> String {
        guard hasPosition else { return "—" }
        return String(format: "%+.3f", position(for: axis))
    }

    var isAlarm: Bool { state.localizedCaseInsensitiveContains("alarm") }
    var isIdle: Bool { state == "Idle" }
    var isOnHold: Bool { state.hasPrefix("Hold") }
}

struct ProgramStatus: Codable, Equatable, Sendable {
    var phase: String? = nil
    var revision: UInt64? = nil
    var currentLine: Int? = nil
    var resumeLine: Int? = nil
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
        case "running":
            if phase == "before" { return "Выполняется предпрограмма" }
            if phase == "after" { return "Выполняется послепрограмма" }
            return "Отправлено \(sent) из \(lines) строк"
        case "completed": return "Выполнена"
        case "canceled": return "Отменена на строке \(lastLine)"
        case "interrupted":
            return "Связь прервана на строке \(lastLine). Повтор прохода со строки \(resumeLine ?? 0)."
                + (error.map { " " + $0 } ?? "")
        case "failed": return "Ошибка в строке \(lastLine)"
        default: return "\(lines) строк"
        }
    }
}

struct ProgramBlocks: Codable, Equatable, Sendable {
    var before: String
    var after: String
    let revision: String
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

struct ControllerSettingGroup: Decodable, Sendable {
    let title: String
    let settings: [ControllerSetting]
}

struct ControllerSetting: Decodable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable { case toggle, integer, decimal }

    let id: String
    let label: String
    let unit: String?
    let kind: Kind
    let min: Double
    let max: Double
    let value: Double?

    var caption: String { unit.map { "$\(id) · \($0)" } ?? "$\(id)" }

    static func number(_ text: String) -> Double? {
        guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")),
              number.isFinite else { return nil }
        return number
    }

    func parse(_ text: String) -> Double? {
        guard let number = Self.number(text), number >= min, number <= max,
              kind == .decimal || number.rounded(.towardZero) == number else { return nil }
        return number
    }

    static func text(_ value: Double) -> String {
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

struct ControllerSettingChange: Encodable, Sendable {
    let from: Double
    let to: Double
}

struct ControllerSettingsDraft {
    private(set) var groups: [ControllerSettingGroup] = []
    var values: [String: String] = [:]

    var edited: [ControllerSetting] {
        groups.flatMap(\.settings).filter { setting in
            guard let original = setting.value, let candidate = values[setting.id] else { return false }
            return ControllerSetting.number(candidate) != original
        }
    }

    mutating func replace(with newGroups: [ControllerSettingGroup], keepingEdits: Bool = false) {
        let originals = keepingEdits ? Dictionary(edited.compactMap { setting in
            setting.value.map { (setting.id, $0) }
        }, uniquingKeysWith: { first, _ in first }) : [:]
        var nextValues: [String: String] = [:]
        for setting in newGroups.flatMap(\.settings) {
            guard let value = setting.value else { continue }
            nextValues[setting.id] = originals[setting.id] == value ? values[setting.id] : ControllerSetting.text(value)
        }
        groups = newGroups
        values = nextValues
    }
}

enum ServerConnection: Equatable {
    case connecting
    case authenticationRequired
    case serverOffline
    case controllerOffline
    case connected

    var title: String {
        switch self {
        case .connecting: return "Подключение…"
        case .authenticationRequired: return "Требуется вход"
        case .serverOffline: return "Сервер недоступен"
        case .controllerOffline: return "Контроллер отключён"
        case .connected: return "Подключено"
        }
    }

    var symbol: String {
        switch self {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .authenticationRequired: return "lock.fill"
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
