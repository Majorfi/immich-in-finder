import Foundation

// Intercepts requests on a session configured with it, so client tests can run
// against canned HTTP responses with no real server. The handler inspects the
// request (usually its path) and returns a status + body, or throws to simulate
// a transport failure.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

// Records "METHOD path" for each intercepted request so tests can assert which
// endpoints were actually hit.
final class RequestLog: @unchecked Sendable {
    private var entries: [String] = []
    private let lock = NSLock()
    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        entries.append("\(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
    }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func contains(_ entry: String) -> Bool { all.contains(entry) }
}

enum MockClient {
    // An ImmichClient whose every request is answered by `handler`.
    static func make(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> ImmichClient {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return ImmichClient(baseURL: URL(string: "https://mock.test")!, apiKey: "k", session: session)
    }

    // Answers every request with the same status + JSON string.
    static func make(status: Int = 200, json: String) -> ImmichClient {
        make { _ in (status, Data(json.utf8)) }
    }

    static func data(_ json: String) -> (Int, Data) { (200, Data(json.utf8)) }
}
