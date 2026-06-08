import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case missingEnv(String)
    case badURL(String)
    case notHTTP(String)
    case httpStatus(path: String, code: Int, body: String?)
    case decoding(path: String, underlying: Error)

    var description: String {
        switch self {
        case .missingEnv(let name):
            return "Missing environment variable: \(name)"
        case .badURL(let value):
            return "Could not build a URL from: \(value)"
        case .notHTTP(let path):
            return "Response was not an HTTP response for: \(path)"
        case .httpStatus(let path, let code, let body):
            let snippet = body ?? "<no body>"
            return "HTTP \(code) for \(path)\n   \(snippet)"
        case .decoding(let path, let underlying):
            return "Failed to decode response for \(path): \(underlying)"
        }
    }
}

struct ImmichClient: Sendable {
    let baseURL: URL
    let apiKey: String
    private let session: URLSession = .shared

    func listAlbums() async throws -> [AlbumSummary] {
        try await getJSON(path: "/api/albums")
    }

    func album(id: String) async throws -> Album {
        try await getJSON(path: "/api/albums/\(id)")
    }

    func downloadOriginal(assetID: String) async throws -> (Data, String?) {
        try await getBytes(path: "/api/assets/\(assetID)/original")
    }

    func downloadThumbnail(assetID: String, size: String?) async throws -> (Data, String?) {
        var path = "/api/assets/\(assetID)/thumbnail"
        if let size, size.isEmpty == false {
            path += "?size=\(size)"
        }
        return try await getBytes(path: path)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw ProbeError.badURL(baseURL.absoluteString + path)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        var request = try makeRequest(path: path)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data: data, path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProbeError.decoding(path: path, underlying: error)
        }
    }

    private func getBytes(path: String) async throws -> (Data, String?) {
        let request = try makeRequest(path: path)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data: data, path: path)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        return (data, contentType)
    }

    private static func ensureOK(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.notHTTP(path)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8)
            throw ProbeError.httpStatus(path: path, code: http.statusCode, body: body)
        }
    }
}
