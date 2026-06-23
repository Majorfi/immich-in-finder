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

enum HTTPMethod: String, Sendable { case get = "GET"; case put = "PUT"; case post = "POST"; case patch = "PATCH"; case delete = "DELETE" }

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
        var normalized = baseURL.absoluteString
        while normalized.hasSuffix("/") { normalized.removeLast() }
        self.baseURL = URL(string: normalized) ?? baseURL
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
        let ID: String
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
        request.httpMethod = HTTPMethod.post.rawValue
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

        // The on-disk envelope persists until the `defer` above fires after this
        // method returns, so a retried upload(fromFile:) re-reads a file that
        // still exists.
        let sealed = request
        let (responseData, response) = try await sendRetrying("/api/assets") {
            try await session.upload(for: sealed, fromFile: envelope)
        }
        try Self.ensureOK(response, path: "/api/assets")
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return UploadResult(ID: decoded.id, isDuplicate: decoded.status == .duplicate)
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
        _ = try await sendJSON(method: .put, path: "/api/albums/\(albumID)/assets", body: AssetIDsRequest(ids: assetIDs))
    }

    func removeAssets(albumID: String, assetIDs: [String]) async throws {
        _ = try await sendJSON(method: .delete, path: "/api/albums/\(albumID)/assets", body: AssetIDsRequest(ids: assetIDs))
    }

    func renameAlbum(ID: String, name: String) async throws -> AlbumSummary {
        let data = try await sendJSON(method: .patch, path: "/api/albums/\(ID)", body: UpdateAlbumRequest(albumName: name))
        return try JSONDecoder().decode(AlbumSummary.self, from: data)
    }

    func createAlbum(name: String) async throws -> AlbumSummary {
        let data = try await sendJSON(method: .post, path: "/api/albums", body: CreateAlbumRequest(albumName: name, assetIds: []))
        return try JSONDecoder().decode(AlbumSummary.self, from: data)
    }

    func trashAssets(assetIDs: [String]) async throws {
        _ = try await sendJSON(method: .delete, path: "/api/assets", body: TrashRequest(ids: assetIDs, force: false))
    }

    // force=true bypasses the trash and deletes irreversibly. Not used by the
    // extension (delete = trash); kept for callers that need a hard delete.
    func deleteAssetsPermanently(assetIDs: [String]) async throws {
        _ = try await sendJSON(method: .delete, path: "/api/assets", body: TrashRequest(ids: assetIDs, force: true))
    }

    // Removes the album grouping; the assets it held stay in the library.
    func deleteAlbum(ID: String) async throws {
        _ = try await send(method: .delete, path: "/api/albums/\(ID)")
    }

    func searchMetadata(takenAfter: String? = nil, takenBefore: String? = nil, albumIDs: [String]? = nil, personIDs: [String]? = nil, tagIDs: [String]? = nil, isFavorite: Bool? = nil, city: String? = nil, country: String? = nil, page: Int, size: Int, order: SortOrder) async throws -> SearchPage {
        let body = MetadataSearchRequest(takenAfter: takenAfter, takenBefore: takenBefore, albumIds: albumIDs, personIds: personIDs, tagIds: tagIDs, isFavorite: isFavorite, city: city, country: country, page: page, size: size, order: order, withExif: true)
        let response: SearchResponse = try await postJSON(path: "/api/search/metadata", body: body)
        return SearchPage(assets: response.assets.items, nextPage: response.assets.nextPage)
    }

    func assetYearRange() async throws -> (oldest: Int, newest: Int)? {
        async let oldestPage = searchMetadata(page: 1, size: 1, order: .asc)
        async let newestPage = searchMetadata(page: 1, size: 1, order: .desc)
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
    private func searchAll(albumIDs: [String]? = nil, personIDs: [String]? = nil, tagIDs: [String]? = nil, isFavorite: Bool? = nil, city: String? = nil, country: String? = nil, takenAfter: String? = nil, takenBefore: String? = nil) async throws -> [Asset] {
        var all: [Asset] = []
        var page = 1
        while true {
            let result = try await searchMetadata(takenAfter: takenAfter, takenBefore: takenBefore, albumIDs: albumIDs, personIDs: personIDs, tagIDs: tagIDs, isFavorite: isFavorite, city: city, country: country, page: page, size: 1000, order: .asc)
            all.append(contentsOf: result.assets)
            guard result.nextPage != nil, result.assets.isEmpty == false else {
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

    // Album membership comes from the album endpoint, not /search/metadata: the
    // latter applies the default visibility filter and drops archived assets, so
    // an album of archived photos would enumerate empty.
    func searchAllAlbum(albumID: String) async throws -> [Asset] {
        let detail: AlbumDetail = try await getJSON(path: "/api/albums/\(albumID)")
        return detail.assets
    }

    func searchAllPerson(personID: String) async throws -> [Asset] {
        try await searchAll(personIDs: [personID])
    }

    func searchAllCity(country: String, city: String) async throws -> [Asset] {
        try await searchAll(city: city, country: country)
    }

    func searchAllTag(tagID: String) async throws -> [Asset] {
        try await searchAll(tagIDs: [tagID])
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

    // One GET returns every non-empty month across the whole library (the server
    // default bucketing), so non-empty years/months derive from this single call
    // instead of probing the server once per candidate period. For an N-year
    // library the old per-period fan-out cost 13·N+2 search POSTs (N+2 for the
    // year list, 12 per month drill-down) with unbounded concurrency; this is one
    // request, regardless of library span.
    func timelineBuckets() async throws -> [TimeBucket] {
        try await getJSON(path: "/api/timeline/buckets")
    }

    // Fall-open semantics: if the bucket fetch fails, keep every candidate month
    // (1...12) rather than collapsing the listing, so one transient error never
    // hides the whole year. Output stays "YYYY-MM" and sorted, as callers/tests
    // (MonthItem, monthBounds) expect.
    func nonEmptyMonths(year: String) async -> [String] {
        guard let buckets = try? await timelineBuckets() else {
            return (1...12).map { String(format: "%@-%02d", year, $0) }
        }
        return buckets
            .map { String($0.timeBucket.prefix(7)) } // "YYYY-MM"
            .filter { $0.hasPrefix("\(year)-") }
            .sorted()
    }

    // Fall-open semantics: if the bucket fetch fails, keep every candidate year
    // in the probed range. Years are the distinct 4-char prefixes of the bucket
    // list, sorted descending to match the previous ordering.
    func nonEmptyYears(oldest: Int, newest: Int) async -> [Int] {
        guard let buckets = try? await timelineBuckets() else {
            return Array(oldest...newest).sorted(by: >)
        }
        let years = Set(buckets.compactMap { Int($0.timeBucket.prefix(4)) })
        return years.sorted(by: >)
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

    // MARK: - Retry / backoff

    private static let maxAttempts = 3
    private static let baseBackoffNanos: UInt64 = 200_000_000 // 200ms

    // A transient URLError is a transport blip worth retrying; a definitive
    // failure (auth, not-connected, cancelled) is not. Kept deliberately narrow
    // so genuine offline/4xx surface immediately.
    private static func isTransient(urlError error: Error) -> Bool {
        switch (error as? URLError)?.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    // HTTP 429 (rate limited) and 5xx (server-side) are transient; 4xx are not.
    private static func isTransient(status code: Int) -> Bool {
        code == 429 || (500...599).contains(code)
    }

    // Wraps a single transport send with a bounded exponential backoff. Retries
    // only TRANSIENT failures (transient URLError, or a 429/5xx response);
    // anything else (including non-2xx 4xx) is returned/rethrown as-is so the
    // caller's `ensureOK` produces identical error semantics for the terminal
    // case. The write mutations routed through here (upload/addAssets/trash...)
    // are safe to retry: Immich dedups uploads by checksum and album/trash
    // mutations are set-based and idempotent.
    private func sendRetrying(
        _ path: String,
        _ send: @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        var attempt = 1
        while true {
            let hasAttemptsLeft = attempt < Self.maxAttempts
            do {
                let (data, response) = try await send()
                if hasAttemptsLeft,
                   let http = response as? HTTPURLResponse,
                   Self.isTransient(status: http.statusCode) {
                    try? await Task.sleep(nanoseconds: Self.backoffNanos(attempt))
                    attempt += 1
                    continue
                }
                return (data, response)
            } catch {
                if hasAttemptsLeft, Self.isTransient(urlError: error) {
                    try? await Task.sleep(nanoseconds: Self.backoffNanos(attempt))
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    private static func backoffNanos(_ attempt: Int) -> UInt64 {
        baseBackoffNanos << (attempt - 1) // base * 2^(attempt-1)
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        var request = try makeRequest(path: path)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let sealed = request
        let (data, response) = try await sendRetrying(path) { try await session.data(for: sealed) }
        try Self.ensureOK(response, path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let data = try await sendJSON(method: .post, path: path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Sends a JSON body with an arbitrary method and returns the raw response
    // data (callers decode it or ignore it). Used by POST/PUT/DELETE writes.
    @discardableResult
    private func sendJSON<Body: Encodable>(method: HTTPMethod, path: String, body: Body) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let sealed = request
        let (data, response) = try await sendRetrying(path) { try await session.data(for: sealed) }
        try Self.ensureOK(response, path: path)
        return data
    }

    // A bodyless request (e.g. DELETE /api/albums/{id}, which rejects a body).
    @discardableResult
    private func send(method: HTTPMethod, path: String) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = method.rawValue
        let sealed = request
        let (data, response) = try await sendRetrying(path) { try await session.data(for: sealed) }
        try Self.ensureOK(response, path: path)
        return data
    }

    private func getBytes(path: String) async throws -> Data {
        let request = try makeRequest(path: path)
        let (data, response) = try await sendRetrying(path) { try await session.data(for: request) }
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
