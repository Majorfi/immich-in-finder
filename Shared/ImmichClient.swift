import Foundation

enum ImmichError: Error, CustomStringConvertible {
    case badURL(String)
    case notHTTP(String)
    case httpStatus(path: String, code: Int)

    var description: String {
        switch self {
        case .badURL(let value):
            return "Could not build a URL from: \(value)"
        case .notHTTP(let path):
            return "Response was not an HTTP response for: \(path)"
        case .httpStatus(let path, let code):
            return "HTTP \(code) for \(path)"
        }
    }
}

struct ImmichClient: Sendable {
    let baseURL: URL
    let apiKey: String
    private let session: URLSession = .shared

    func album(id: String) async throws -> Album {
        try await getJSON(path: "/api/albums/\(id)")
    }

    func listAlbums() async throws -> [AlbumSummary] {
        try await getJSON(path: "/api/albums")
    }

    func asset(id: String) async throws -> Asset {
        try await getJSON(path: "/api/assets/\(id)")
    }

    func downloadOriginal(assetID: String) async throws -> Data {
        try await getBytes(path: "/api/assets/\(assetID)/original")
    }

    func downloadThumbnail(assetID: String, size: String?) async throws -> Data {
        var path = "/api/assets/\(assetID)/thumbnail"
        if let size, size.isEmpty == false {
            path += "?size=\(size)"
        }
        return try await getBytes(path: path)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw ImmichError.badURL(baseURL.absoluteString + path)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        var request = try makeRequest(path: path)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getBytes(path: String) async throws -> Data {
        let request = try makeRequest(path: path)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, path: path)
        return data
    }

    private static func ensureOK(_ response: URLResponse, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ImmichError.notHTTP(path)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ImmichError.httpStatus(path: path, code: http.statusCode)
        }
    }
}
