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

struct SearchPage: Sendable {
    let assets: [Asset]
    let nextPage: String?
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

    func searchMetadata(takenAfter: String?, takenBefore: String?, page: Int, size: Int, order: String) async throws -> SearchPage {
        let body = MetadataSearchRequest(takenAfter: takenAfter, takenBefore: takenBefore, page: page, size: size, order: order)
        let response: SearchResponse = try await postJSON(path: "/api/search/metadata", body: body)
        return SearchPage(assets: response.assets.items, nextPage: response.assets.nextPage)
    }

    func assetYearRange() async throws -> (oldest: Int, newest: Int)? {
        async let oldestPage = searchMetadata(takenAfter: nil, takenBefore: nil, page: 1, size: 1, order: "asc")
        async let newestPage = searchMetadata(takenAfter: nil, takenBefore: nil, page: 1, size: 1, order: "desc")
        let (oldest, newest) = try await (oldestPage, newestPage)
        guard let oldestYear = oldest.assets.first.flatMap({ Int($0.fileCreatedAt.prefix(4)) }),
              let newestYear = newest.assets.first.flatMap({ Int($0.fileCreatedAt.prefix(4)) }) else {
            return nil
        }
        return (oldestYear, newestYear)
    }

    func searchMonth(yearMonth: String, page: Int) async throws -> SearchPage {
        let bounds = ImmichClient.monthBounds(yearMonth)
        return try await searchMetadata(takenAfter: bounds.after, takenBefore: bounds.before, page: page, size: 250, order: "asc")
    }

    func searchAllMonth(yearMonth: String) async throws -> [Asset] {
        var all: [Asset] = []
        var page = 1
        while true {
            let result = try await searchMonth(yearMonth: yearMonth, page: page)
            all.append(contentsOf: result.assets)
            guard result.nextPage != nil else {
                break
            }
            page += 1
        }
        return all
    }

    func hasAssets(after: String, before: String) async throws -> Bool {
        let page = try await searchMetadata(takenAfter: after, takenBefore: before, page: 1, size: 1, order: "asc")
        return page.assets.isEmpty == false
    }

    func monthHasAssets(_ yearMonth: String) async throws -> Bool {
        let bounds = ImmichClient.monthBounds(yearMonth)
        return try await hasAssets(after: bounds.after, before: bounds.before)
    }

    func yearHasAssets(_ year: Int) async throws -> Bool {
        let after = String(format: "%04d-01-01T00:00:00.000Z", year)
        let before = String(format: "%04d-01-01T00:00:00.000Z", year + 1)
        return try await hasAssets(after: after, before: before)
    }

    // A failing probe falls open (the candidate is kept) so one transient error
    // never collapses the whole listing.
    func nonEmptyMonths(year: String) async -> [String] {
        let candidates = (1...12).map { String(format: "%@-%02d", year, $0) }
        let kept = await ImmichClient.concurrentFilter(candidates) { yearMonth in
            (try? await self.monthHasAssets(yearMonth)) ?? true
        }
        return kept.sorted()
    }

    func nonEmptyYears(oldest: Int, newest: Int) async -> [Int] {
        let candidates = Array(oldest...newest)
        let kept = await ImmichClient.concurrentFilter(candidates) { year in
            (try? await self.yearHasAssets(year)) ?? true
        }
        return kept.sorted(by: >)
    }

    static func concurrentFilter<T: Sendable>(_ candidates: [T], keep: @Sendable @escaping (T) async -> Bool) async -> [T] {
        await withTaskGroup(of: (T, Bool).self) { group in
            for candidate in candidates {
                group.addTask { (candidate, await keep(candidate)) }
            }
            var kept: [T] = []
            for await (candidate, keepIt) in group {
                if keepIt {
                    kept.append(candidate)
                }
            }
            return kept
        }
    }

    static func monthBounds(_ yearMonth: String) -> (after: String, before: String) {
        let parts = yearMonth.split(separator: "-")
        var year = 1970
        if let parsed = parts.first.flatMap({ Int($0) }) {
            year = parsed
        }
        var month = 1
        if parts.count > 1, let parsed = Int(parts[1]) {
            month = parsed
        }
        let after = String(format: "%04d-%02d-01T00:00:00.000Z", year, month)
        let nextYear: Int
        let nextMonth: Int
        if month == 12 {
            nextYear = year + 1
            nextMonth = 1
        } else {
            nextYear = year
            nextMonth = month + 1
        }
        let before = String(format: "%04d-%02d-01T00:00:00.000Z", nextYear, nextMonth)
        return (after, before)
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

    private func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
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
