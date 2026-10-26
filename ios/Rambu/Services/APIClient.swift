import Foundation

struct APIError: LocalizedError, Sendable {
    let status: Int
    let detail: String

    var errorDescription: String? { detail }
    var isUnreachable: Bool { status == 0 }
}

/// Talks to the Rambu backend. The base URL is the Server address setting (a quick tunnel can change it).
struct APIClient: Sendable {
    var baseURL: URL
    var token: String?

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: Optional<[String: String]>.none)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: String] = [:]) async throws -> T {
        try await send("POST", path, body: body)
    }

    func put(_ path: String, _ body: [String: String]) async throws {
        let _: Empty = try await send("PUT", path, body: body)
    }

    func health() async -> Bool {
        do {
            let reply: [String: Bool] = try await get("/health")
            return reply["ok"] == true
        } catch {
            return false
        }
    }

    private struct Empty: Decodable {}

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 15)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(status: 0, detail: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "HTTP \(status)"
            throw APIError(status: status, detail: detail)
        }
        if T.self == Empty.self || data.isEmpty {
            return try Self.decoder.decode(T.self, from: Data("{}".utf8))
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
