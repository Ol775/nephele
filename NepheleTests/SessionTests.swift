import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct SessionTests {
    let goodToken = String(repeating: "a", count: 40)

    func tokenStore() -> TokenStore { TokenStore(service: "io.github.ol775.nephele.tests.\(UUID().uuidString)") }
    nonisolated static func ok(_ result: String) -> Data { Data("{\"success\":true,\"errors\":[],\"result\":\(result),\"result_info\":{\"page\":1,\"per_page\":50,\"total_pages\":1,\"total_count\":1}}".utf8) }
    nonisolated static let forbidden = Data("{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}".utf8)

    /// A stub account: verify ok, one account, one zone, empty lists elsewhere; `deny` paths answer 403.
    func server(deny: [String] = [], verifyStatus: Int = 200) -> StubServer {
        return StubServer { req in
            let path = req.url!.path
            if path.hasSuffix("/user/tokens/verify") {
                return (StubURLProtocol.response(req.url!, status: verifyStatus), verifyStatus == 200 ? Self.ok("{\"id\":\"tok1\",\"status\":\"active\"}") : Data("{\"success\":false,\"errors\":[{\"code\":1000,\"message\":\"Invalid API Token\"}],\"result\":null}".utf8))
            }
            if deny.contains(where: { path.contains($0) }) { return (StubURLProtocol.response(req.url!, status: 403), Self.forbidden) }
            if path.hasSuffix("/accounts") { return (StubURLProtocol.response(req.url!), Self.ok("[{\"id\":\"acc1\",\"name\":\"Example account\"}]")) }
            if path.hasSuffix("/zones") { return (StubURLProtocol.response(req.url!), Self.ok("[{\"id\":\"z1\",\"name\":\"example.dev\",\"status\":\"active\",\"paused\":false,\"name_servers\":[],\"plan\":{\"name\":\"Free\"},\"account\":{\"id\":\"acc1\"}}]")) }
            return (StubURLProtocol.response(req.url!), Self.ok("[]"))
        }
    }

    func session(_ stub: StubServer, _ store: TokenStore) -> Session {
        Session(tokenStore: store, makeClient: { CFClient(token: $0, session: stub.session) })
    }

    @Test func plausibleTokenRequires40AllowedCharacters() {
        #expect(Session.isPlausibleToken(goodToken))
        #expect(Session.isPlausibleToken(String(repeating: "A_-", count: 13) + "a"))
        #expect(!Session.isPlausibleToken("short"))
        #expect(!Session.isPlausibleToken(String(repeating: "a", count: 41)))
        #expect(!Session.isPlausibleToken(String(repeating: "a", count: 39) + "!"))
    }

    @Test func signInWithValidTokenStoresItAndBecomesReady() async throws {
        let store = tokenStore(); defer { store.delete() }
        let s = session(server(), store)
        try await s.signIn(token: goodToken)
        #expect(s.state == .ready)
        #expect(s.accounts.map(\.id) == ["acc1"])
        #expect(s.selectedAccountID == "acc1")
        #expect(store.load() == goodToken)
        #expect(s.client != nil)
    }

    @Test func signInWithInvalidTokenStaysSignedOutAndStoresNothing() async {
        let store = tokenStore(); defer { store.delete() }
        let s = session(server(verifyStatus: 401), store)
        await #expect(throws: CloudflareError.unauthorized) { try await s.signIn(token: goodToken) }
        #expect(s.state == .signedOut)
        #expect(store.load() == nil)
    }

    @Test func malformedTokenIsRejectedBeforeAnyRequest() async {
        let store = tokenStore(); defer { store.delete() }
        let stub = server()
        let s = session(stub, store)
        await #expect(throws: SignInError.invalidFormat) { try await s.signIn(token: "nope") }
        #expect(stub.recorded.isEmpty)
        #expect(store.load() == nil)
    }

    @Test func restoreUsesStoredToken() async throws {
        let store = tokenStore(); defer { store.delete() }
        try store.save(goodToken)
        let s = session(server(), store)
        await s.restore()
        #expect(s.state == .ready)
    }

    @Test func restoreWithNoStoredTokenStaysSignedOut() async {
        let store = tokenStore()
        let s = session(server(), store)
        await s.restore()
        #expect(s.state == .signedOut)
    }

    @Test func restoreWithNetworkErrorKeepsTheStoredToken() async throws {
        let store = tokenStore(); defer { store.delete() }
        try store.save(goodToken)
        let s = session(StubServer { _ in throw URLError(.notConnectedToInternet) }, store)
        await s.restore()
        #expect(s.state == .signedOut)
        #expect(s.signInError != nil)
        #expect(store.load() == goodToken)
    }

    @Test func unauthorizedErrorSignsOutAndClearsToken() async throws {
        let store = tokenStore(); defer { store.delete() }
        let s = session(server(), store)
        try await s.signIn(token: goodToken)
        s.handle(.unauthorized)
        #expect(s.state == .signedOut)
        #expect(store.load() == nil)
        #expect(s.client == nil)
    }

    @Test func permissionDeniedDoesNotSignOut() async throws {
        let store = tokenStore(); defer { store.delete() }
        let s = session(server(), store)
        try await s.signIn(token: goodToken)
        s.handle(.permissionDenied("nope"))
        #expect(s.state == .ready)
        #expect(store.load() == goodToken)
    }

    @Test func permissionsListSurfacesMissingOnes() async throws {
        let store = tokenStore(); defer { store.delete() }
        let s = session(server(deny: ["/cfd_tunnel", "/r2/buckets"]), store)
        try await s.signIn(token: goodToken)
        #expect(Set(s.missingPermissions.map(\.name)) == ["Cloudflare Tunnel", "Workers R2 Storage"])
        #expect(s.state == .ready)
    }
}
