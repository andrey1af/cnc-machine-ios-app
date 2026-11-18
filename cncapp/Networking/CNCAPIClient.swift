import Foundation

struct CNCAPIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func preview() async throws -> ToolpathPreview {
        var request = URLRequest(url: try url(for: "/api/program/preview"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return try JSONDecoder().decode(ToolpathPreview.self, from: await execute(request))
    }

    func post(_ path: String, json: [String: Any] = [:]) async throws {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        _ = try await execute(request)
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

    private func execute(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CNCClientError.invalidResponse
            }
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

enum CNCClientError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case network(String)
    case server(status: Int, message: String, details: String?)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Некорректный адрес сервера"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .network(let message):
            return "Нет связи с сервером: \(message)"
        case .server(_, let message, let details):
            if let details, !details.isEmpty { return "\(message): \(details)" }
            return message
        }
    }
}
