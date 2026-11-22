import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct ProtectionTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    func ok(_ json: String) -> String { "{\"success\":true,\"errors\":[],\"result\":\(json)}" }
    func stub(_ body: String, status: Int = 200) -> StubServer { StubServer { req in (StubURLProtocol.response(req.url!, status: status), Data(body.utf8)) } }
    func bodyOf(_ r: StubServer.Recorded) -> String { String(decoding: r.body ?? Data(), as: UTF8.self) }

    @Test func emailRuleReadsFromAndDestinations() async throws {
        let s = stub(ok("[{\"id\":\"r1\",\"name\":\"x\",\"enabled\":true,\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"a@e.dev\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"me@e.com\"]}]},{\"id\":\"r2\",\"matchers\":[{\"type\":\"all\"}],\"actions\":[{\"type\":\"drop\"}]}]"))
        let rules = try await client(s).emailRules(zoneID: "z1")
        #expect(rules[0].from == "a@e.dev" && rules[0].destinations == ["me@e.com"] && rules[0].isForward)
        #expect(rules[1].from == nil && !rules[1].isForward)
        #expect(s.recorded[0].request.url?.path == "/client/v4/zones/z1/email/routing/rules")
    }

    @Test func createEmailRuleSendsALiteralToForward() async throws {
        let s = stub(ok("{\"id\":\"n\"}"))
        _ = try await client(s).createEmailRule(zoneID: "z1", address: " Hi@E.dev ", destination: "me@e.com")
        let r = try #require(s.recorded.first)
        #expect(r.request.httpMethod == "POST")
        #expect(bodyOf(r).contains("\"value\":\"hi@e.dev\"") && bodyOf(r).contains("\"type\":\"forward\"") && bodyOf(r).contains("me@e.com"))
        await #expect(throws: CloudflareError.self) { _ = try await client(s).createEmailRule(zoneID: "z1", address: "nope", destination: "me@e.com") }
        #expect(s.recorded.count == 1)
    }

    @Test func toggleEmailRuleResendsTheWholeRule() async throws {
        let s = stub(ok("{\"id\":\"r1\"}"))
        let rule = EmailRule(id: "r1", name: "n", enabled: true, priority: 3, matchers: [EmailMatcher(type: "literal", field: "to", value: "a@e.dev")], actions: [EmailAction(type: "forward", value: ["me@e.com"])])
        _ = try await client(s).setEmailRule(zoneID: "z1", rule: rule, enabled: false)
        let r = try #require(s.recorded.first)
        #expect(r.request.httpMethod == "PUT" && r.request.url?.path.hasSuffix("/rules/r1") == true)
        #expect(bodyOf(r).contains("\"enabled\":false") && bodyOf(r).contains("a@e.dev") && bodyOf(r).contains("\"priority\":3"))
    }

    @Test func validEmailRejectsTypos() {
        #expect(validEmail("a@b.co") && !validEmail("a@b") && !validEmail("@b.co") && !validEmail("a b@c.co") && !validEmail("a@@b.co"))
    }

    @Test func missingFirewallRulesetIsNilNotAnError() async throws {
        let s = stub("{\"success\":false,\"errors\":[{\"code\":10003,\"message\":\"could not find entrypoint ruleset\"}],\"result\":null}", status: 404)
        #expect(try await client(s).firewallRuleset(zoneID: "z1") == nil)
        #expect(s.recorded[0].request.url?.path == "/client/v4/zones/z1/rulesets/phases/http_request_firewall_custom/entrypoint")
        let denied = stub("{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}", status: 403)
        await #expect(throws: CloudflareError.self) { _ = try await client(denied).firewallRuleset(zoneID: "z1") }
    }

    @Test func createFirewallRulePostsToTheRulesetOrCreatesIt() async throws {
        let s = stub(ok("{\"id\":\"rs\",\"rules\":[]}"))
        let d = FirewallRuleDraft(action: "block", expression: "(ip.src eq 1.2.3.4)", description: "bad")
        _ = try await client(s).createFirewallRule(zoneID: "z1", rulesetID: "rs", d)
        _ = try await client(s).createFirewallRule(zoneID: "z1", rulesetID: nil, d)
        #expect(s.recorded[0].request.httpMethod == "POST" && s.recorded[0].request.url?.path.hasSuffix("/rulesets/rs/rules") == true)
        #expect(s.recorded[1].request.httpMethod == "PUT" && s.recorded[1].request.url?.path.hasSuffix("/phases/http_request_firewall_custom/entrypoint") == true)
        #expect(bodyOf(s.recorded[1]).contains("\"rules\":["))
        await #expect(throws: CloudflareError.self) { _ = try await client(s).createFirewallRule(zoneID: "z1", rulesetID: "rs", FirewallRuleDraft(action: "block", expression: "  ", description: "")) }
        await #expect(throws: CloudflareError.self) { _ = try await client(s).createFirewallRule(zoneID: "z1", rulesetID: "rs", FirewallRuleDraft(action: "execute", expression: "true", description: "")) }
        #expect(s.recorded.count == 2)
    }

    @Test func toggleFirewallRulePatchesWithTheWholeRule() async throws {
        let s = stub(ok("{\"id\":\"rs\"}"))
        _ = try await client(s).setFirewallRule(zoneID: "z1", rulesetID: "rs", rule: FirewallRule(id: "r1", action: "block", expression: "true", description: "d", enabled: true), enabled: false)
        let r = try #require(s.recorded.first)
        #expect(r.request.httpMethod == "PATCH" && r.request.url?.path.hasSuffix("/rulesets/rs/rules/r1") == true)
        #expect(bodyOf(r).contains("\"enabled\":false") && bodyOf(r).contains("\"action\":\"block\""))
    }

    @Test func turnstileCreateReturnsTheSecretOnceAndKeepsItOutOfTheWidget() async throws {
        let s = stub(ok("{\"sitekey\":\"0xAA\",\"secret\":\"SEKRET\",\"name\":\"site\",\"mode\":\"managed\",\"domains\":[\"e.dev\"]}"))
        let made = try await client(s).createTurnstile(accountID: "a1", name: "site", domains: ["e.dev"], mode: "managed")
        #expect(made.secret == "SEKRET" && made.widget.sitekey == "0xAA")
        #expect(!String(describing: made).contains("SEKRET") && !String(reflecting: made).contains("SEKRET"))
        #expect(bodyOf(s.recorded[0]).contains("\"domains\":[\"e.dev\"]"))
        await #expect(throws: CloudflareError.self) { _ = try await client(s).createTurnstile(accountID: "a1", name: "site", domains: ["https://e.dev/x"], mode: "managed") }
        await #expect(throws: CloudflareError.self) { _ = try await client(s).createTurnstile(accountID: "a1", name: "site", domains: [], mode: "managed") }
        #expect(s.recorded.count == 1)
    }

    @Test func turnstileDomainParsing() {
        #expect(parseTurnstileDomains("A.dev, b.dev\n c.dev ") == ["a.dev", "b.dev", "c.dev"])
        #expect(validHostname("a.dev") && !validHostname("a") && !validHostname("a.dev/x") && !validHostname("http://a.dev"))
    }

    @Test func gatewayRulesListAndDelete() async throws {
        let s = stub(ok("[{\"id\":\"g1\",\"name\":\"Block ads\",\"action\":\"block\",\"enabled\":true,\"filters\":[\"dns\"],\"precedence\":10}]"))
        let rules = try await client(s).gatewayRules(accountID: "a1")
        #expect(rules.first?.name == "Block ads" && rules.first?.filters == ["dns"])
        try await client(s).deleteGatewayRule(accountID: "a1", id: "g1")
        #expect(s.recorded[1].request.httpMethod == "DELETE" && s.recorded[1].request.url?.path == "/client/v4/accounts/a1/gateway/rules/g1")
    }
}
