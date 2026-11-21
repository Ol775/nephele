import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct AccountTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "tok_SECRET123", session: stub.session) }
    let emptyOK = Data("{\"success\":true,\"errors\":[],\"result\":[]}".utf8)
    let forbidden = Data("{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}".utf8)

    @Test func verifyTokenDecodesActiveStatus() async throws {
            let stub = StubServer(); stub.handler = { req in
            #expect(req.url?.path == "/client/v4/user/tokens/verify")
            return (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"tokid1\",\"status\":\"active\"}}".utf8))
        }
        let status = try await client(stub).verifyToken()
        #expect(status == TokenStatus(id: "tokid1", status: "active"))
    }

    @Test func verifyTokenThrowsUnauthorizedOnInvalid() async {
            let stub = StubServer(); stub.handler = { req in (StubURLProtocol.response(req.url!, status: 401), Data("{\"success\":false,\"errors\":[{\"code\":1000,\"message\":\"Invalid API Token\"}],\"result\":null}".utf8)) }
        let c = client(stub)
        await #expect(throws: CloudflareError.unauthorized) { _ = try await c.verifyToken() }
    }

    @Test func accountsDecodesNameAndId() async throws {
            let stub = StubServer(); stub.handler = { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":[{\"id\":\"acc1\",\"name\":\"Example account\"}],\"result_info\":{\"page\":1,\"per_page\":50,\"total_pages\":1,\"total_count\":1}}".utf8)) }
        let accounts = try await client(stub).accounts()
        #expect(accounts == [CFAccount(id: "acc1", name: "Example account")])
    }

    @Test func probeMarksForbiddenEndpointsAsMissing() async {        let ok = emptyOK, no = forbidden
        let stub = StubServer(); stub.handler = { req in
            let p = req.url!.path
            if p.contains("/cfd_tunnel") || p.contains("/r2/buckets") { return (StubURLProtocol.response(req.url!, status: 403), no) }
            return (StubURLProtocol.response(req.url!), ok)
        }
        let result = await client(stub).probePermissions(accountID: "acc1", zoneID: "z1")
        #expect(result.count == 9)
        #expect(Set(result.filter { !$0.granted }.map(\.name)) == ["Cloudflare Tunnel", "Workers R2 Storage"])
        #expect(result.allSatisfy { $0.level == "Read (edit not checked)" })
    }

    @Test func probeSkipsDNSWhenThereIsNoZone() async {        let ok = emptyOK
        let stub = StubServer(); stub.handler = { req in (StubURLProtocol.response(req.url!), ok) }
        let result = await client(stub).probePermissions(accountID: "acc1", zoneID: nil)
        #expect(result.count == 8)
        #expect(!result.contains { $0.name == "DNS" })
    }

    @Test func probeNeverThrows() async {
            let stub = StubServer(); stub.handler = { _ in throw URLError(.notConnectedToInternet) }
        let result = await client(stub).probePermissions(accountID: "acc1", zoneID: "z1")
        #expect(result.count == 9)
        #expect(result.allSatisfy { !$0.granted })
    }

    @Test func verifyAccountTokenUsesTheAccountEndpoint() async throws {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"tokid2\",\"status\":\"active\"}}".utf8))
        }
        let status = try await CFClient(token: "t", session: stub.session).verifyToken(accountID: "acc1")
        #expect(status.status == "active")
        #expect(stub.recorded[0].request.url?.path == "/client/v4/accounts/acc1/tokens/verify")
    }
}
