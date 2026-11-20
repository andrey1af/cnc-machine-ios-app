import Foundation

final class SSEClient: RejectRedirects, URLSessionDataDelegate, @unchecked Sendable {
    var onEvent: (@Sendable (_ event: String, _ data: String) -> Void)?
    var onDisconnect: (@Sendable (_ error: Error?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var currentEvent = "message"
    private var currentData: [String] = []
    private let lock = NSLock()
    private var stopped = false

    func start(request: URLRequest) {
        stop()
        lock.withLock { stopped = false }
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = .infinity
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = newSession
        task = newSession.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        lock.withLock {
            stopped = true
            buffer.removeAll(keepingCapacity: false)
            currentEvent = "message"
            currentData.removeAll(keepingCapacity: false)
        }
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            completionHandler(.allow)
        } else {
            let requiresPassword = (response as? HTTPURLResponse)?.statusCode == 401
            notifyDisconnect(requiresPassword ? CNCClientError.authenticationRequired : CNCClientError.invalidResponse)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock {
            guard !stopped else { return }
            buffer.append(data)
            consumeCompleteLines()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        notifyDisconnect(error)
    }

    private func notifyDisconnect(_ error: Error?) {
        let shouldNotify = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            return true
        }
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
