import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct ProtectionStoreTests {
    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    // MARK: Email Routing
    func email(denyWrites: Bool = false) async throws -> (EmailRoutingStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "POST" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"n1\",\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"new@example.dev\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"me@e.com\"]}],\"enabled\":true}")) }
            if req.httpMethod == "PUT" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"r1\",\"enabled\":false,\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"hi@example.dev\"}]}")) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"r1\"}")) }
            if p.hasSuffix("/email/routing/rules") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"r1\",\"enabled\":true,\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"hi@example.dev\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"me@e.com\"]}]}]")) }
            if p.hasSuffix("/email/routing/addresses") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"d1\",\"email\":\"me@e.com\",\"verified\":\"2026-01-01T00:00:00Z\"},{\"id\":\"d2\",\"email\":\"pending@e.com\",\"verified\":null}]")) }
            if p.hasSuffix("/email/routing") { return TestAPI.reply(req, TestAPI.ok("{\"enabled\":true,\"status\":\"ready\"}")) }
            return TestAPI.base(req)
        }
        let s = EmailRoutingStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await s.load()
        return (s, stub)
    }

    @Test func emailLoadsRulesAndOnlyVerifiedDestinationsCount() async throws {
        let (s, _) = try await email()
        #expect(s.rules.value?.first?.from == "hi@example.dev" && s.addresses.count == 2 && s.verified.map(\.email) == ["me@e.com"])
    }

    @Test func emailCreateChecksAddressDomainAndVerifiedDestination() async throws {
        let (s, stub) = try await email()
        await s.create(address: "nope", destination: "me@e.com"); #expect(s.formError != nil)
        await s.create(address: "x@other.dev", destination: "me@e.com"); #expect(s.formError?.contains("example.dev") == true)
        await s.create(address: "x@example.dev", destination: "pending@e.com"); #expect(s.formError?.contains("verified") == true)
        #expect(writes(stub).isEmpty)
        await s.create(address: "new@example.dev", destination: "me@e.com")
        #expect(s.formError == nil && s.rules.value?.count == 2 && writes(stub).count == 1)
    }

    @Test func emailToggleAndDeleteNeedConfirmationOnlyForDelete() async throws {
        let (s, stub) = try await email()
        let r = try #require(s.rules.value?.first)
        await s.toggle(r)
        #expect(s.rules.value?.first?.enabled == false && writes(stub).count == 1)
        s.requestDelete(r)
        #expect(writes(stub).count == 1)
        let change = try #require(s.confirm.pending)
        await s.confirmChange(change); await s.confirmChange(change)
        #expect(s.rules.value?.isEmpty == true && writes(stub).count == 2)
    }

    @Test func emailForbiddenLocksWrites() async throws {
        let (s, _) = try await email(denyWrites: true)
        await s.toggle(try #require(s.rules.value?.first))
        #expect(!s.canWrite && s.formError?.contains("Email Routing Rules Edit") == true && s.rules.value?.count == 1)
    }

    // MARK: WAF
    func waf(hasRuleset: Bool = true, denyWrites: Bool = false) async throws -> (FirewallStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "PUT" || req.httpMethod == "POST" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"rs\",\"rules\":[{\"id\":\"r1\",\"action\":\"block\",\"expression\":\"true\",\"enabled\":true},{\"id\":\"r2\",\"action\":\"log\",\"expression\":\"false\",\"enabled\":true}]}")) }
            if req.httpMethod == "PATCH" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"rs\",\"rules\":[{\"id\":\"r1\",\"action\":\"block\",\"expression\":\"true\",\"enabled\":false}]}")) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if p.hasSuffix("/entrypoint") {
                if !hasRuleset { return TestAPI.reply(req, "{\"success\":false,\"errors\":[{\"code\":10003,\"message\":\"could not find entrypoint ruleset\"}],\"result\":null}", status: 404) }
                return TestAPI.reply(req, TestAPI.ok("{\"id\":\"rs\",\"rules\":[{\"id\":\"r1\",\"action\":\"block\",\"expression\":\"true\",\"enabled\":true}]}"))
            }
            return TestAPI.base(req)
        }
        let s = FirewallStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await s.load()
        return (s, stub)
    }

    @Test func wafNoRulesetMeansAnEmptyListAndFirstRuleCreatesIt() async throws {
        let (s, stub) = try await waf(hasRuleset: false)
        #expect(s.rules.value?.isEmpty == true)
        let d = FirewallRuleDraft(action: "block", expression: "(ip.src eq 1.2.3.4)", description: "x")
        s.request(.create(d))
        #expect(writes(stub).isEmpty)
        await s.confirmChange(try #require(s.confirm.pending))
        #expect(writes(stub).first?.request.httpMethod == "PUT" && s.rules.value?.count == 2)
    }

    @Test func wafInvalidDraftNeverReachesTheConfirmation() async throws {
        let (s, stub) = try await waf()
        s.request(.create(FirewallRuleDraft(action: "block", expression: " ", description: "")))
        #expect(s.confirm.pending == nil && s.formError != nil && writes(stub).isEmpty)
    }

    @Test func wafDisableIsImmediateButEnableAndDeleteAreConfirmed() async throws {
        let (s, stub) = try await waf()
        let r = try #require(s.rules.value?.first)
        await s.disable(r)
        #expect(s.rules.value?.first?.enabled == false && writes(stub).count == 1 && writes(stub)[0].request.httpMethod == "PATCH")
        s.request(.delete(r)); #expect(writes(stub).count == 1)
        await s.confirmChange(try #require(s.confirm.pending))
        #expect(s.rules.value?.isEmpty == true && writes(stub).count == 2)
    }

    @Test func wafForbiddenLocksWritesAndKeepsTheList() async throws {
        let (s, _) = try await waf(denyWrites: true)
        await s.disable(try #require(s.rules.value?.first))
        #expect(!s.canWrite && s.formError?.contains("Zone WAF Edit") == true && s.rules.value?.count == 1)
    }

    @Test func wafMessagesWarnAboutLockout() {
        #expect(FirewallChange.create(FirewallRuleDraft(action: "block", expression: "x", description: "")).message.contains("lock"))
        #expect(!FirewallChange.create(FirewallRuleDraft(action: "log", expression: "x", description: "")).message.contains("lock"))
    }

    // MARK: Turnstile
    func turnstile(denyWrites: Bool = false) async throws -> (TurnstileStore, StubServer) {
        let stub = StubServer { req in
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "POST" { return TestAPI.reply(req, TestAPI.ok("{\"sitekey\":\"0xN\",\"secret\":\"SEKRET\",\"name\":\"fresh\",\"mode\":\"managed\",\"domains\":[\"e.dev\"]}")) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("{\"sitekey\":\"0xA\"}")) }
            if req.url!.path.hasSuffix("/challenges/widgets") { return TestAPI.reply(req, TestAPI.ok("[{\"sitekey\":\"0xA\",\"name\":\"zed\"},{\"sitekey\":\"0xB\",\"name\":\"alpha\"}]")) }
            return TestAPI.base(req)
        }
        let s = TurnstileStore(session: try await TestAPI.readySession(stub))
        await s.load()
        return (s, stub)
    }

    @Test func turnstileLoadsSortedAndCreateHandsOverTheSecretOnce() async throws {
        let (s, stub) = try await turnstile()
        #expect(s.widgets.value?.map(\.name) == ["alpha", "zed"])
        await s.create(name: "fresh", domains: "https://e.dev", mode: "managed")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.create(name: "fresh", domains: "e.dev", mode: "managed")
        #expect(s.newSecret?.secret == "SEKRET" && s.widgets.value?.contains { $0.sitekey == "0xN" } == true)
        #expect(!"\(s.widgets)".contains("SEKRET"))
        s.dismissSecret(); #expect(s.newSecret == nil)
    }

    @Test func turnstileDeleteNeedsTheTypedName() async throws {
        let (s, stub) = try await turnstile()
        let w = try #require(s.widgets.value?.first)
        await s.delete(w, typedName: "alph"); #expect(s.formError != nil && writes(stub).isEmpty)
        await s.delete(w, typedName: "alpha"); #expect(s.widgets.value?.map(\.name) == ["zed"])
    }

    @Test func turnstileForbiddenLocksWritesAndResetKeepsAPendingSecret() async throws {
        let (s, _) = try await turnstile(denyWrites: true)
        await s.create(name: "fresh", domains: "e.dev", mode: "managed")
        #expect(!s.canWrite && s.formError?.contains("Turnstile Sites Edit") == true)
        let (t, _) = try await turnstile()
        await t.create(name: "fresh", domains: "e.dev", mode: "managed"); t.reset()
        #expect(t.widgets.value == nil && t.newSecret?.secret == "SEKRET")
    }

    // MARK: Gateway (in ZeroTrustStore)
    @Test func gatewayRulesLoadInPrecedenceOrderAndDeleteNeedsTheTypedName() async throws {
        let stub = StubServer { req in
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if req.url!.path.hasSuffix("/gateway/rules") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"g2\",\"name\":\"B\",\"precedence\":20},{\"id\":\"g1\",\"name\":\"A\",\"precedence\":10}]")) }
            return TestAPI.base(req)
        }
        let s = ZeroTrustStore(session: try await TestAPI.readySession(stub))
        await s.loadAll()
        #expect(s.gateway.value?.map(\.name) == ["A", "B"])
        let g = try #require(s.gateway.value?.first)
        await s.delete(.gateway(g), typedName: "a")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.delete(.gateway(g), typedName: "A")
        #expect(s.gateway.value?.map(\.name) == ["B"] && writes(stub).count == 1)
    }
}
