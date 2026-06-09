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
    private let session: URLSession

    // session is injectable so tests can drive a mocked URLProtocol; production
    // callers get the shared session.
    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
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

    // MARK: - Write

    struct UploadResult: Sendable {
        let id: String
        let isDuplicate: Bool
    }

    // Uploads a file as a new asset. The multipart envelope is assembled on disk
    // (the source is streamed in by chunks) and sent with upload(fromFile:), so
    // the asset is never held in memory — large videos won't blow the heap or
    // starve the cooperative thread pool. Immich dedups by checksum, so an
    // identical file returns status "duplicate" with the existing asset's id.
    func uploadAsset(filename: String, fileURL: URL, createdAt: String, modifiedAt: String) async throws -> UploadResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: "/api/assets")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let envelope = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: envelope) }
        try await Self.writeMultipartEnvelope(
            to: envelope, boundary: boundary, filename: filename, source: fileURL,
            fields: [
                ("deviceAssetId", "immich-in-finder-\(UUID().uuidString)"),
                ("deviceId", "immich-in-finder"),
                ("fileCreatedAt", createdAt),
                ("fileModifiedAt", modifiedAt),
            ]
        )

        let (responseData, response) = try await session.upload(for: request, fromFile: envelope)
        try Self.ensureOK(response, path: "/api/assets")
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return UploadResult(id: decoded.id, isDuplicate: decoded.status == "duplicate")
    }

    // Builds the multipart body on disk on a background queue (off the
    // cooperative pool), copying the source file in bounded chunks.
    private static func writeMultipartEnvelope(to url: URL, boundary: String, filename: String, source: URL, fields: [(String, String)]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    var prefix = Data()
                    for (name, value) in fields {
                        prefix.appendString("--\(boundary)\r\n")
                        prefix.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                        prefix.appendString("\(value)\r\n")
                    }
                    prefix.appendString("--\(boundary)\r\n")
                    prefix.appendString("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(filename)\"\r\n")
                    prefix.appendString("Content-Type: application/octet-stream\r\n\r\n")

                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let writer = try FileHandle(forWritingTo: url)
                    defer { try? writer.close() }
                    try writer.write(contentsOf: prefix)
                    let reader = try FileHandle(forReadingFrom: source)
                    defer { try? reader.close() }
                    while let chunk = try reader.read(upToCount: 1 << 20), chunk.isEmpty == false {
                        try writer.write(contentsOf: chunk)
                    }
                    try writer.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func addAssets(albumID: String, assetIDs: [String]) async throws {
        _ = try await sendJSON(method: "PUT", path: "/api/albums/\(albumID)/assets", body: AssetIDsRequest(ids: assetIDs))
    }

    func removeAssets(albumID: String, assetIDs: [String]) async throws {
        _ = try await sendJSON(method: "DELETE", path: "/api/albums/\(albumID)/assets", body: AssetIDsRequest(ids: assetIDs))
    }

    func renameAlbum(id: String, name: String) async throws -> AlbumSummary {
        let data = try await sendJSON(method: "PATCH", path: "/api/albums/\(id)", body: UpdateAlbumRequest(albumName: name))
        return try JSONDecoder().decode(AlbumSummary.self, from: data)
    }

    func createAlbum(name: String) async throws -> AlbumSummary {
        let data = try await sendJSON(method: "POST", path: "/api/albums", body: CreateAlbumRequest(albumName: name, assetIds: []))
        return try JSONDecoder().decode(AlbumSummary.self, from: data)
    }

    func trashAssets(assetIDs: [String]) async throws {
        _ = try await sendJSON(method: "DELETE", path: "/api/assets", body: TrashRequest(ids: assetIDs, force: false))
    }

    // force=true bypasses the trash and deletes irreversibly. Not used by the
    // extension (delete = trash); kept for callers that need a hard delete.
    func deleteAssetsPermanently(assetIDs: [String]) async throws {
        _ = try await sendJSON(method: "DELETE", path: "/api/assets", body: TrashRequest(ids: assetIDs, force: true))
    }

    // Removes the album grouping; the assets it held stay in the library.
    func deleteAlbum(id: String) async throws {
        _ = try await send(method: "DELETE", path: "/api/albums/\(id)")
    }

    func searchMetadata(takenAfter: String? = nil, takenBefore: String? = nil, albumIds: [String]? = nil, personIds: [String]? = nil, tagIds: [String]? = nil, isFavorite: Bool? = nil, city: String? = nil, country: String? = nil, page: Int, size: Int, order: String) async throws -> SearchPage {
        let body = MetadataSearchRequest(takenAfter: takenAfter, takenBefore: takenBefore, albumIds: albumIds, personIds: personIds, tagIds: tagIds, isFavorite: isFavorite, city: city, country: country, page: page, size: size, order: order, withExif: true)
        let response: SearchResponse = try await postJSON(path: "/api/search/metadata", body: body)
        return SearchPage(assets: response.assets.items, nextPage: response.assets.nextPage)
    }

    func assetYearRange() async throws -> (oldest: Int, newest: Int)? {
        async let oldestPage = searchMetadata(page: 1, size: 1, order: "asc")
        async let newestPage = searchMetadata(page: 1, size: 1, order: "desc")
        let (oldest, newest) = try await (oldestPage, newestPage)
        guard let oldestYear = oldest.assets.first.flatMap({ Int($0.fileCreatedAt.prefix(4)) }),
              let newestYear = newest.assets.first.flatMap({ Int($0.fileCreatedAt.prefix(4)) }) else {
            return nil
        }
        return (oldestYear, newestYear)
    }

    // Pages through /api/search/metadata until exhausted, gathering every asset
    // matching the filter. Backs both the month (timeline) and album views, so
    // album enumeration is bounded by page size instead of one unbounded fetch.
    private func searchAll(albumIds: [String]? = nil, personIds: [String]? = nil, tagIds: [String]? = nil, isFavorite: Bool? = nil, city: String? = nil, country: String? = nil, takenAfter: String? = nil, takenBefore: String? = nil) async throws -> [Asset] {
        var all: [Asset] = []
        var page = 1
        while true {
            let result = try await searchMetadata(takenAfter: takenAfter, takenBefore: takenBefore, albumIds: albumIds, personIds: personIds, tagIds: tagIds, isFavorite: isFavorite, city: city, country: country, page: page, size: 250, order: "asc")
            all.append(contentsOf: result.assets)
            guard result.nextPage != nil else {
                break
            }
            page += 1
        }
        return all
    }

    func searchAllMonth(yearMonth: String) async throws -> [Asset] {
        let bounds = ImmichClient.monthBounds(yearMonth)
        return try await searchAll(takenAfter: bounds.after, takenBefore: bounds.before)
    }

    func searchAllAlbum(albumID: String) async throws -> [Asset] {
        try await searchAll(albumIds: [albumID])
    }

    func searchAllPerson(personID: String) async throws -> [Asset] {
        try await searchAll(personIds: [personID])
    }

    func searchAllCity(country: String, city: String) async throws -> [Asset] {
        try await searchAll(city: city, country: country)
    }

    func searchAllTag(tagID: String) async throws -> [Asset] {
        try await searchAll(tagIds: [tagID])
    }

    func listTags() async throws -> [TagSummary] {
        try await getJSON(path: "/api/tags")
    }

    func searchAllFavorites() async throws -> [Asset] {
        try await searchAll(isFavorite: true)
    }

    // Distinct (country, city) places — the cities endpoint returns one
    // representative asset per city, carrying its exif location.
    func listCities() async throws -> [PlaceSummary] {
        let assets: [Asset] = try await getJSON(path: "/api/search/cities")
        return assets.compactMap { asset in
            guard let country = asset.exifInfo?.country, country.isEmpty == false,
                  let city = asset.exifInfo?.city, city.isEmpty == false else {
                return nil
            }
            return PlaceSummary(country: country, city: city)
        }
    }

    // Named, non-hidden people only — unnamed face clusters aren't useful folders.
    func listPeople() async throws -> [PersonSummary] {
        var all: [PersonSummary] = []
        var page = 1
        while true {
            let response: PeopleResponse = try await getJSON(path: "/api/people?page=\(page)&size=500&withHidden=false")
            all.append(contentsOf: response.people)
            guard response.hasNextPage == true else {
                break
            }
            page += 1
        }
        return all.filter { $0.name?.isEmpty == false }
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
        let data = try await sendJSON(method: "POST", path: path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Sends a JSON body with an arbitrary method and returns the raw response
    // data (callers decode it or ignore it). Used by POST/PUT/DELETE writes.
    @discardableResult
    private func sendJSON<Body: Encodable>(method: String, path: String, body: Body) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, path: path)
        return data
    }

    // A bodyless request (e.g. DELETE /api/albums/{id}, which rejects a body).
    @discardableResult
    private func send(method: String, path: String) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, path: path)
        return data
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

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
