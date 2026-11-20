import Foundation

final class CameraStreamClient: RejectRedirects, URLSessionDataDelegate, @unchecked Sendable {
    struct Stream {
        let frames: AsyncThrowingStream<Data, Error>
        fileprivate let session: URLSession

        func cancel() { session.invalidateAndCancel() }
    }

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var frame: JPEGFrameBuffer?

    private init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.continuation = continuation
    }

    static func open(request: URLRequest) -> Stream {
        let (frames, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let delegate = CameraStreamClient(continuation: continuation)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        continuation.onTermination = { _ in session.invalidateAndCancel() }

        var request = request
        request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
        session.dataTask(with: request).resume()
        return Stream(frames: frames, session: session)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            if let http = response as? HTTPURLResponse {
                try validateStatus(http.statusCode)
            }
            // URLSession вызывает didReceive response для каждой части multipart.
            switch response.mimeType?.lowercased() {
            case "image/jpeg":
                try finishFrame()
                frame = try JPEGFrameBuffer(expectedLength: response.expectedContentLength)
            case "multipart/x-mixed-replace":
                break
            default:
                throw JPEGFrameBuffer.InvalidFrame()
            }
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard frame != nil else { throw JPEGFrameBuffer.InvalidFrame() }
            if let jpeg = try frame?.append(data) {
                frame = nil
                continuation.yield(jpeg)
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        do {
            try finishFrame()
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func finishFrame() throws {
        if let frame {
            continuation.yield(try frame.finish())
            self.frame = nil
        }
    }

    private func validateStatus(_ status: Int) throws {
        switch status {
        case 200:
            return
        case 401:
            throw CNCClientError.authenticationRequired
        case 404:
            throw CNCClientError.server(status: 404, message: "Камера не настроена на Repka", details: nil)
        case 503:
            throw CNCClientError.server(status: 503, message: "Repka не получает кадры с USB-камеры", details: nil)
        default:
            throw CNCClientError.server(status: status, message: "Не удалось открыть видеопоток", details: nil)
        }
    }
}
