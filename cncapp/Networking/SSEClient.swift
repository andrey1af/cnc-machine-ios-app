import Foundation

final class SSEClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onEvent: (@Sendable (_ event: String, _ data: String) -> Void)?
    var onDisconnect: (@Sendable (_ error: Error?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var currentEvent = "message"
    private var currentData: [String] = []
    private let lock = NSLock()
    private var stopped = false

    func start(url: URL) {
        stop()
        lock.withLock { stopped = false }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = .infinity
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = newSession
        task = newSession.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        lock.withLock { stopped = true }
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll(keepingCapacity: false)
        currentEvent = "message"
        currentData.removeAll(keepingCapacity: false)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        consumeCompleteLines()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let shouldNotify = lock.withLock { !stopped }
        if shouldNotify { onDisconnect?(error) }
    }

    private func consumeCompleteLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            process(line: String(decoding: lineData, as: UTF8.self))
        }
    }

    private func process(line: String) {
        if line.isEmpty {
            if !currentData.isEmpty {
                onEvent?(currentEvent, currentData.joined(separator: "\n"))
            }
            currentEvent = "message"
            currentData.removeAll(keepingCapacity: true)
            return
        }
        if line.hasPrefix(":") { return }
        if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
