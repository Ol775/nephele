import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct ZeroTrustStoreTests {
    func make(denyWrites: Bool = false, deleteError: Bool = false) async throws -> (ZeroTrustStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "DELETE" {
                if deleteError { return TestAPI.reply(req, "{\"success\":false,\"errors\":[{\"code\":1022,\"message\":\"Tunnel has active connections\"}],\"result\":null}", status: 400) }
                return TestAPI.reply(req, TestAPI.ok("null"))
            }
            if req.httpMethod == "POST" && p.hasSuffix("/cfd_tunnel") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"t9\",\"name\":\"fresh\"}")) }
            if req.httpMethod == "POST" && p.hasSuffix("/service_tokens") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"s9\",\"name\":\"ci\",\"client_id\":\"c.access\",\"client_secret\":\"SEKRET\"}")) }
            if p.hasSuffix("/cfd_tunnel") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"t1\",\"name\":\"zeta\",\"status\":\"healthy\"},{\"id\":\"t2\",\"name\":\"alpha\",\"status\":\"inactive\"}]")) }
            if p.hasSuffix("/access/apps") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"a1\",\"name\":\"Vault\",\"domain\":\"v.example.dev\"}]")) }
            if p.hasSuffix("/service_tokens") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"s1\",\"name\":\"old\",\"client_id\":\"o.access\"}]")) }
            return TestAPI.base(req)
        }
        let store = ZeroTrustStore(session: try await TestAPI.readySession(stub))
        await store.loadAll()
        return (store, stub)
    }
    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsEachListAndSortsTunnelsByName() async throws {
        let (s, _) = try await make()
        #expect(s.tunnels.value?.map(\.name) == ["alpha", "zeta"])
        #expect(s.apps.value?.count == 1 && s.tokens.value?.count == 1)
    }

    @Test func deleteNeedsTheTypedNameForEachKind() async throws {
        let (s, stub) = try await make()
        let t = try #require(s.tunnels.value?.first)
        await s.delete(.tunnel(t), typedName: "alph")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.delete(.tunnel(t), typedName: "alpha")
        #expect(s.tunnels.value?.map(\.name) == ["zeta"] && writes(stub).count == 1)
        await s.delete(.app(try #require(s.apps.value?.first)), typedName: "Vault")
        await s.delete(.token(try #require(s.tokens.value?.first)), typedName: "old")
        #expect(s.apps.value?.isEmpty == true && s.tokens.value?.isEmpty == true)
    }

    @Test func failedTunnelDeleteKeepsTheListAndShowsTheAPIMessage() async throws {
        let (s, _) = try await make(deleteError: true)
        let t = try #require(s.tunnels.value?.first)
        await s.delete(.tunnel(t), typedName: "alpha")
        #expect(s.tunnels.value?.count == 2)
        #expect(s.formError?.contains("active connections") == true)
    }

    @Test func createTunnelValidatesAndAdds() async throws {
        let (s, stub) = try await make()
        await s.createTunnel("  ")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.createTunnel("fresh")
        #expect(s.tunnels.value?.map(\.name).contains("fresh") == true)
    }

    @Test func secretIsHandedOverOnceAndNeverKeptInTheList() async throws {
        let (s, _) = try await make()
        await s.createToken(name: "ci", duration: "8760h")
        #expect(s.tokens.value?.contains { $0.id == "s9" } == true)
        #expect(s.newSecret?.secret == "SEKRET")
        s.dismissSecret()
        #expect(s.newSecret == nil)
        #expect(!"\(s.tokens)".contains("SEKRET"))
    }

    @Test func forbiddenWriteTurnsWritesOffWithAHint() async throws {
        let (s, _) = try await make(denyWrites: true)
        await s.createTunnel("fresh")
        #expect(!s.canWrite && s.formError?.contains("Cloudflare Tunnel Write") == true)
    }

    @Test func accountSwitchDropsLateResultsAndResetClears() async throws {
        let (s, _) = try await make()
        s.reset()
        #expect(s.tunnels.value == nil && s.newSecret == nil && s.formError == nil && s.canWrite)
    }
}
