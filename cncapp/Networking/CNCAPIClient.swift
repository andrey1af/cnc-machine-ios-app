import Foundation

struct CNCAPIClient: Sendable {
    private static let sessionCookie = "__Host-repka_session"
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func signIn(password: String) async throws {
        guard baseURL.scheme?.lowercased() == "https" else { throw CNCClientError.passwordRequiresHTTPS }
        let loginURL = try url(for: "/login")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "password", value: password)]

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (_, response) = try await session.data(for: request, delegate: RejectRedirects())
        guard let http = response as? HTTPURLResponse else { throw CNCClientError.invalidResponse }
        if http.statusCode == 401 {
            throw CNCClientError.server(status: 401, message: "Неверный пароль веб-пульта", details: nil)
        }
        guard http.statusCode == 303,
              let header = http.value(forHTTPHeaderField: "Set-Cookie"),
              let cookie = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: loginURL)
                .first(where: { $0.name == Self.sessionCookie && $0.isSecure && $0.path == "/" && $0.domain == loginURL.host }),
              let storage = session.configuration.httpCookieStorage else {
            throw CNCClientError.invalidResponse
        }
        storage.setCookie(cookie)
    }

    func eventsRequest() throws -> URLRequest { try streamRequest(for: "/api/events") }

    func cameraStream() throws -> CameraStreamClient.Stream {
        try CameraStreamClient.open(request: streamRequest(for: "/api/camera/stream"))
    }

    func preview() async throws -> ToolpathPreview {
        var request = URLRequest(url: try url(for: "/api/program/preview"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return try JSONDecoder().decode(ToolpathPreview.self, from: await execute(request))
    }

    func controllerSettings(changes: [String: ControllerSettingChange]? = nil) async throws -> [ControllerSettingGroup] {
        let url = try url(for: "/api/controller/settings")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let changes {
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(changes)
        }
        do {
            return try JSONDecoder().decode([ControllerSettingGroup].self, from: await execute(request))
        } catch CNCClientError.server(let status, _, _) where status == 404 || status == 405 {
            throw CNCClientError.server(status: status, message: "Обновите cncbridge на Repka для работы с настройками контроллера", details: nil)
        }
    }

    func post(_ path: String, json: [String: Any] = [:]) async throws {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        _ = try await execute(request)
    }

    func programBlocks(saving blocks: ProgramBlocks? = nil) async throws -> ProgramBlocks {
        let url = try url(for: "/api/program/blocks")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if let blocks {
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(blocks)
        }
        return try JSONDecoder().decode(ProgramBlocks.self, from: await execute(request))
    }

    func uploadProgram(data: Data, name: String) async throws -> ProgramResponse {
        var components = URLComponents(url: try url(for: "/api/program"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components?.url else { throw CNCClientError.invalidAddress }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let responseData = try await execute(request)
        return try JSONDecoder().decode(ProgramResponse.self, from: responseData)
    }

    private func url(for path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw CNCClientError.invalidAddress
        }
        return url
    }

    private func streamRequest(for path: String) throws -> URLRequest {
        let url = try url(for: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if url.scheme?.lowercased() == "https",
           let cookies = session.configuration.httpCookieStorage?.cookies(for: url),
           let cookie = cookies.first(where: { $0.name == Self.sessionCookie && $0.isSecure }) {
            request.setValue(HTTPCookie.requestHeaderFields(with: [cookie])["Cookie"], forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CNCClientError.invalidResponse
            }
            if http.statusCode == 401 { throw CNCClientError.authenticationRequired }
            guard (200...299).contains(http.statusCode) else {
                let serverError = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw CNCClientError.server(
                    status: http.statusCode,
                    message: serverError?.message ?? "Сервер вернул ошибку",
                    details: serverError?.details
                )
            }
            return data
        } catch let error as CNCClientError {
            throw error
        } catch {
            throw CNCClientError.network(error.localizedDescription)
        }
    }
}

class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum CNCClientError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case authenticationRequired
    case passwordRequiresHTTPS
    case network(String)
    case server(status: Int, message: String, details: String?)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Некорректный адрес сервера"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .authenticationRequired:
            return "Введите пароль веб-пульта в настройках подключения"
        case .passwordRequiresHTTPS:
            return "Для входа укажите HTTPS-адрес Repka"
        case .network(let message):
            return "Нет связи с сервером: \(message)"
        case .server(_, let message, let details):
            if let details, !details.isEmpty { return "\(message): \(details)" }
            return message
        }
    }
}
