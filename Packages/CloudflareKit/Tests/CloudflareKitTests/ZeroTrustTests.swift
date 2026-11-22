import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct ZeroTrustTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    let ok = Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)

    @Test func tunnelsDecodeWithStatusAndConnections() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("tunnels")) }
        let list = try await client(stub).tunnels(accountID: "acc1")
        #expect(list.map(\.name) == ["homelab", "old"])
        #expect(list[0].status == "healthy" && list[0].connections?.first?.coloName == "LHR")
        #expect(list[1].connections == nil)
        let q = stub.recorded.first?.request.url?.query ?? ""
        #expect(q.contains("is_deleted=false"))
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/cfd_tunnel")
    }

    @Test func createTunnelValidatesThenPostsCloudflareManaged() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"t9\",\"name\":\"new-one\"}}".utf8)) }
        let t = try await client(stub).createTunnel(accountID: "acc1", name: "new-one")
        #expect(t.id == "t9")
        let body = String(data: try #require(stub.recorded.first?.body), encoding: .utf8) ?? ""
        #expect(body.contains("\"config_src\":\"cloudflare\"") && body.contains("\"name\":\"new-one\""))
        let c = client(stub)
        await #expect(throws: WorkerValidationError.invalidName) { _ = try await c.createTunnel(accountID: "acc1", name: "  ") }
        #expect(stub.recorded.count == 1)
    }

    @Test func deleteTunnelAndAppAndTokenUseDeleteWithEncodedIDs() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        let c = client(stub)
        try await c.deleteTunnel(accountID: "acc1", id: "t/1")
        try await c.deleteAccessApp(accountID: "acc1", id: "a1")
        try await c.deleteServiceToken(accountID: "acc1", id: "s1")
        #expect(stub.recorded.map { $0.request.httpMethod } == ["DELETE", "DELETE", "DELETE"])
        #expect(stub.recorded[0].request.url?.absoluteString.hasSuffix("/cfd_tunnel/t%2F1") == true)
        #expect(stub.recorded[1].request.url?.path.hasSuffix("/access/apps/a1") == true)
    }

    @Test func accessAppsTolerateMissingFields() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("access-apps")) }
        let apps = try await client(stub).accessApps(accountID: "acc1")
        #expect(apps[0].domain == "vault.example.dev" && apps[0].policies?.count == 2 && apps[0].sessionDuration == "24h")
        #expect(apps[1].domain == nil && apps[1].type == nil)
    }

    @Test func serviceTokensListHasNoSecretAndCreateReturnsItOnce() async throws {
        let stub = StubServer { req in
            if req.httpMethod == "POST" { return (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"s3\",\"name\":\"new\",\"client_id\":\"cid.access\",\"client_secret\":\"SECRET-VALUE\",\"duration\":\"8760h\"}}".utf8)) }
            return (StubURLProtocol.response(req.url!), fixture("service-tokens"))
        }
        let c = client(stub)
        let list = try await c.serviceTokens(accountID: "acc1")
        #expect(list.map(\.clientID) == ["abc.access", nil])
        let made = try await c.createServiceToken(accountID: "acc1", name: "new", duration: "8760h")
        #expect(made.clientSecret == "SECRET-VALUE" && made.token.id == "s3")
        await #expect(throws: WorkerValidationError.invalidName) { _ = try await c.createServiceToken(accountID: "acc1", name: "", duration: "8760h") }
    }

    @Test func tunnelNameRules() {
        #expect(validTunnelName("home-lab 1") && !validTunnelName(" ") && !validTunnelName(String(repeating: "a", count: 101)))
    }
}
