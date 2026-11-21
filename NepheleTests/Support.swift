import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

/// Shared fake Cloudflare account for app tests: sign-in endpoints answer, everything else is an empty list.
enum TestAPI {
    static let goodToken = String(repeating: "a", count: 40)
    static let forbiddenBody = "{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}"
    static let zoneJSON = "{\"id\":\"z1\",\"name\":\"example.dev\",\"status\":\"active\",\"paused\":false,\"name_servers\":[\"ada.ns.example.net\"],\"plan\":{\"name\":\"Free\"},\"account\":{\"id\":\"acc1\"}}"

    static func ok(_ result: String) -> String {
        "{\"success\":true,\"errors\":[],\"result\":\(result),\"result_info\":{\"page\":1,\"per_page\":50,\"total_pages\":1,\"total_count\":1}}"
    }

    static func reply(_ req: URLRequest, _ body: String, status: Int = 200) -> (HTTPURLResponse, Data) {
        (StubURLProtocol.response(req.url!, status: status), Data(body.utf8))
    }

    static func base(_ req: URLRequest, deny: [String] = [], verifyStatus: Int = 200, tokenState: String = "active") -> (HTTPURLResponse, Data) {
        let path = req.url!.path
        if path.hasSuffix("/tokens/verify") {
            return verifyStatus == 200
                ? reply(req, ok("{\"id\":\"tok1\",\"status\":\"\(tokenState)\"}"))
                : reply(req, "{\"success\":false,\"errors\":[{\"code\":1000,\"message\":\"Invalid API Token\"}],\"result\":null}", status: verifyStatus)
        }
        if deny.contains(where: { path.contains($0) }) { return reply(req, forbiddenBody, status: 403) }
        if path.hasSuffix("/accounts") { return reply(req, ok("[{\"id\":\"acc1\",\"name\":\"Example account\"}]")) }
        if path.hasSuffix("/zones") { return reply(req, ok("[\(zoneJSON)]")) }
        return reply(req, ok("[]"))
    }

    /// A signed-in session whose Keychain item is removed straight away so tests leave nothing behind.
    @MainActor static func readySession(_ stub: StubServer) async throws -> Session {
        let store = TokenStore(service: "io.github.ol775.nephele.tests.\(UUID().uuidString)")
        let session = Session(tokenStore: store, makeClient: { CFClient(token: $0, session: stub.session) })
        try await session.signIn(token: goodToken)
        store.delete()
        return session
    }

    static var zone: Zone { Zone(id: "z1", name: "example.dev", status: "active", planName: "Free", nameServers: ["ada.ns.example.net"], accountID: "acc1") }
}

/// Lets a test change how the fake account answers while it runs.
final class Flags: @unchecked Sendable {
    private let lock = NSLock()
    private var _verifyStatus = 200, _tokenState = "active"
    var verifyStatus: Int { get { lock.withLock { _verifyStatus } } set { lock.withLock { _verifyStatus = newValue } } }
    var tokenState: String { get { lock.withLock { _tokenState } } set { lock.withLock { _tokenState = newValue } } }
    var offline = false
    func handle(_ req: URLRequest) throws -> (HTTPURLResponse, Data) {
        if offline { throw URLError(.notConnectedToInternet) }
        return TestAPI.base(req, verifyStatus: verifyStatus, tokenState: tokenState)
    }
}
