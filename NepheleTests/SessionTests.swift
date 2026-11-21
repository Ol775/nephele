import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct SessionTests {
    let goodToken = String(repeating: "a", count: 40)

    func tokenStore() -> TokenStore { TokenStore(service: "io.github.ol775.nephele.tests.\(UUID().uuidString)") }
    func server(deny: [String] = [], verifyStatus: Int = 200) -> StubServer {
        StubServer { req in TestAPI.base(req, deny: deny, verifyStatus: verifyStatus) }
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
