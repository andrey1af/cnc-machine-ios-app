import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LogStore: ObservableObject {
    struct Snapshot {
        var all: [LogEntry] = []
        var standard: [LogEntry] = []
    }

    @Published private(set) var snapshot = Snapshot()

    func append(_ entry: LogEntry) {
        var next = snapshot
        next.all.append(entry)
        if next.all.count > 1_000 {
            let removed = next.all.removeFirst()
            if removed.level != "DEBUG" { next.standard.removeFirst() }
        }
        if entry.level != "DEBUG" { next.standard.append(entry) }
        snapshot = next
    }

    func clear() { snapshot = Snapshot() }
}

@MainActor
final class MachineViewModel: ObservableObject {
    @Published private(set) var status = MachineStatus.disconnected
    @Published private(set) var connection: ServerConnection = .connecting
    let logStore = LogStore()
    @Published var isUploading = false
    @Published var lastError: String?
    @Published var serverAddress: String

    @Published private(set) var preview: ToolpathPreview?
    @Published private(set) var previewError: String?
    @Published private(set) var previewEpoch = 0
    @Published private(set) var previewRenderVersion = 0

    var previewKey: String { "\(client.baseURL)-\(previewEpoch)-\(status.program.revision ?? 0)" }

    private var loadedPreviewKey: String?

    func loadPreview(force: Bool = false) async {
        let key = previewKey
        if !force, loadedPreviewKey == key, preview != nil { return }
        preview = nil
        loadedPreviewKey = nil
        previewError = nil
        guard (status.program.revision ?? 0) > 0 else { return }
        do {
            let result = try await client.preview()
            guard !Task.isCancelled, key == previewKey else { return }
            guard result.revision == status.program.revision else {
                previewError = "Траектория обновляется. Повторите загрузку."
                return
            }
            preview = result
            loadedPreviewKey = key
            previewRenderVersion += 1
        } catch {
            guard !Task.isCancelled, key == previewKey else { return }
            previewError = "Не удалось загрузить траекторию"
        }
    }

    private var client: CNCAPIClient
    private var eventClient: SSEClient?
    private var jogTask: Task<Void, Never>?
    private var jogRepeated = false
    private var lastLogID: Int64 = 0
    private var serverBoot: Int64 = 0
    private var localLogID: Int64 = -1
    private var generation = UUID()

    init() {
        let saved = UserDefaults.standard.string(forKey: "cnc.serverAddress") ?? "http://repka.local:8080"
        let normalized = Self.normalizedAddress(saved) ?? "http://repka.local:8080"
        serverAddress = normalized
        client = CNCAPIClient(baseURL: URL(string: normalized)!)
    }

    deinit {
        eventClient?.stop()
        jogTask?.cancel()
    }

    func connect() {
        generation = UUID()
        eventClient?.stop()
        eventClient = nil
        status.connected = false
        connection = .connecting
        startEventStream()
    }

    func disconnect() {
        generation = UUID()
        eventClient?.stop()
        eventClient = nil
        connection = .serverOffline
        status.connected = false
    }

    @discardableResult
    func applyServerAddress() -> Bool {
        guard let normalized = Self.normalizedAddress(serverAddress), let url = URL(string: normalized) else {
            lastError = "Введите адрес вида http://repka.local:8080"
            return false
        }
        let addressChanged = client.baseURL.absoluteString != normalized
        serverAddress = normalized
        UserDefaults.standard.set(normalized, forKey: "cnc.serverAddress")
        if addressChanged {
            client = CNCAPIClient(baseURL: url)
            lastLogID = 0
            serverBoot = 0
            logStore.clear()
        }
        connect()
        return true
    }

    func dismissError() { lastError = nil }

    func beginJog(axis: Axis, direction: Int) {
        guard status.connected, !status.program.running else { return }
        endJog()
        jogRepeated = false

        // Первый шаг не привязан к задаче удержания: короткое касание
        // не должно отменять уже отправляемый HTTP-запрос.
        Task { [weak self] in
            await self?.sendJog(axis: axis, direction: direction, reportError: true)
        }

        jogTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            while !Task.isCancelled {
                self.jogRepeated = true
                await self.sendJog(axis: axis, direction: direction, reportError: false)
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    func endJog() {
        guard jogTask != nil else { return }
        jogTask?.cancel()
        jogTask = nil
        if jogRepeated { Task { await stopJog() } }
        jogRepeated = false
    }

    func stopJog() async {
        jogTask?.cancel()
        jogTask = nil
        await perform(path: "/api/stop", action: "остановка перемещения", silent: false)
    }

    func emergencyStop() async {
        endJog()
        await perform(path: "/api/reset", action: "аварийная остановка")
    }

    func unlock() async { await perform(path: "/api/unlock", action: "снятие блокировки") }
    func home() async { await perform(path: "/api/home", action: "хоминг") }
    func zero() async { await perform(path: "/api/zero", action: "обнуление координат") }

    func updateStep(_ value: Double) async {
        await perform(path: "/api/settings", json: ["step": min(max(value, 0.1), 50)], action: "изменение шага")
    }

    func updateFeedXY(_ value: Double) async {
        await perform(path: "/api/settings", json: ["feedXY": min(max(value, 1), 300)], action: "изменение скорости X/Y")
    }

    func updateFeedZ(_ value: Double) async {
        await perform(path: "/api/settings", json: ["feedZ": min(max(value, 1), 300)], action: "изменение скорости Z")
    }

    func uploadProgram(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Не удалось получить доступ к выбранному файлу"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isUploading = true
        defer { isUploading = false }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            if let size = values.fileSize, size > 10 * 1_024 * 1_024 {
                throw CNCClientError.server(status: 413, message: "Файл больше 10 МБ", details: nil)
            }
            let data = try Data(contentsOf: url)
            let response = try await client.uploadProgram(data: data, name: values.name ?? url.lastPathComponent)
            addLocalLog(level: "INFO", message: "Загружена программа \(response.name), строк: \(response.lines)")
        } catch {
            report(error, action: "загрузка программы")
        }
    }

    func startProgram() async { await perform(path: "/api/program/start", action: "запуск программы") }
    func pauseProgram() async { await perform(path: "/api/program/pause", action: "пауза программы") }
    func resumeProgram() async { await perform(path: "/api/program/resume", action: "продолжение программы") }
    func cancelProgram() async { await perform(path: "/api/program/cancel", action: "отмена программы") }

    private func sendJog(axis: Axis, direction: Int, reportError: Bool) async {
        do {
            try await client.post("/api/jog", json: ["axis": axis.rawValue, "dir": direction])
        } catch CNCClientError.server(let status, _, _) where status == 429 {
            // Ожидаемый ответ при удержании: сервер не накапливает движения в очереди.
        } catch {
            if reportError { self.report(error, action: "перемещение \(axis.rawValue)") }
        }
    }

    private func perform(
        path: String,
        json: [String: Any] = [:],
        action: String,
        silent: Bool = false
    ) async {
        do {
            try await client.post(path, json: json)
        } catch {
            if !silent { report(error, action: action) }
        }
    }

    private func startEventStream() {
        guard let baseURL = URL(string: serverAddress),
              let eventsURL = URL(string: "/api/events", relativeTo: baseURL)?.absoluteURL else {
            lastError = "Некорректный адрес сервера"
            connection = .serverOffline
            return
        }

        generation = UUID()
        let currentGeneration = generation
        let stream = SSEClient()
        stream.onEvent = { [weak self] event, data in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.receive(event: event, data: data)
            }
        }
        stream.onDisconnect = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.handleDisconnect(error)
            }
        }
        eventClient = stream
        stream.start(url: eventsURL)
    }

    private func receive(event: String, data: String) {
        guard let payload = data.data(using: .utf8) else { return }
        switch event {
        case "hello":
            guard let hello = try? JSONDecoder().decode(HelloEvent.self, from: payload) else { return }
            if serverBoot != 0, serverBoot != hello.boot {
                addLocalLog(level: "INFO", message: "Сервер перезапущен")
                lastLogID = 0
            }
            if serverBoot != hello.boot { previewEpoch += 1 }
            serverBoot = hello.boot
        case "log":
            guard let entry = try? JSONDecoder().decode(LogEntry.self, from: payload), entry.id > lastLogID else { return }
            lastLogID = entry.id
            logStore.append(entry)
        case "status":
            guard let newStatus = try? JSONDecoder().decode(MachineStatus.self, from: payload) else { return }
            status = newStatus
            connection = newStatus.connected ? .connected : .controllerOffline
        default:
            break
        }
    }

    private func handleDisconnect(_ error: Error?) {
        generation = UUID()
        connection = .serverOffline
        status.connected = false
        endJog()
        eventClient?.stop()
        eventClient = nil
    }

    private func report(_ error: Error, action: String) {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let message = "\(action): \(detail)"
        lastError = message
        addLocalLog(level: "ERROR", message: message)
    }

    private func addLocalLog(level: String, message: String) {
        let entry = LogEntry(
            id: localLogID,
            time: ISO8601DateFormatter.withFractionalSeconds.string(from: Date()),
            level: level,
            msg: message,
            attrs: nil
        )
        localLogID -= 1
        logStore.append(entry)
    }

    private static func normalizedAddress(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://" + value }
        while value.last == "/" { value.removeLast() }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        return value
    }
}
