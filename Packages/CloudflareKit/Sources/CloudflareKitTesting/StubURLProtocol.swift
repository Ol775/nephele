import Foundation

/// A stubbed network for tests. Each `StubServer` owns its own URLSession and handler,
/// so tests that use different servers can run in parallel.
public final class StubServer: @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    public struct Recorded: Sendable { public let request: URLRequest; public let body: Data? }

    public let id = UUID().uuidString
    public private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [StubURLProtocol.header: id]
        return URLSession(configuration: config)
    }()

    private let lock = NSLock()
    private var _handler: Handler?
    private var _recorded: [Recorded] = []

    public init(_ handler: Handler? = nil) {
        _handler = handler
        StubURLProtocol.register(self)
    }
    deinit { StubURLProtocol.unregister(id) }

    public var handler: Handler? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    public var recorded: [Recorded] { lock.withLock { _recorded } }
    func record(_ r: Recorded) { lock.withLock { _recorded.append(r) } }
}

public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let header = "X-Stub-ID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: Unmanaged<StubServer>] = [:]

    static func register(_ s: StubServer) { lock.withLock { servers[s.id] = Unmanaged.passUnretained(s) } }
    static func unregister(_ id: String) { lock.withLock { servers[id] = nil } }
    private static func server(for id: String?) -> StubServer? {
        lock.withLock { id.flatMap { servers[$0]?.takeUnretainedValue() } }
    }

    public static func response(_ url: URL, status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        guard let server = Self.server(for: request.value(forHTTPHeaderField: Self.header)) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        server.record(.init(request: request, body: body))
        guard let handler = server.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            var forHandler = request
            forHandler.httpBodyStream = nil
            forHandler.httpBody = body
            let (response, data) = try handler(forHandler)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override public func stopLoading() {}
}
