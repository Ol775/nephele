import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct DNSTests {
    func draft(_ type: String = "A", name: String = "api", content: String = "192.0.2.10", proxied: Bool = true, priority: Int? = nil) -> DNSRecordDraft {
        DNSRecordDraft(type: type, name: name, content: content, proxied: proxied, priority: priority)
    }
    func record(_ id: String) -> String { "{\"id\":\"\(id)\",\"type\":\"A\",\"name\":\"example.dev\",\"content\":\"192.0.2.10\",\"proxied\":true,\"ttl\":1}" }
    func list(_ ids: [String], page: Int = 1, totalPages: Int = 1) -> Data {
        Data("{\"success\":true,\"errors\":[],\"result\":[\(ids.map(record).joined(separator: ","))],\"result_info\":{\"page\":\(page),\"per_page\":100,\"total_pages\":\(totalPages),\"total_count\":\(ids.count)}}".utf8)
    }
    func single(_ id: String) -> Data { Data("{\"success\":true,\"errors\":[],\"result\":\(record(id))}".utf8) }

    @Test func apexAtBecomesZoneName() throws {
        #expect(try draft(name: "@").validated(zone: "example.dev").name == "example.dev")
    }
    @Test func relativeNameGetsZoneSuffixAndLowercase() throws {
        #expect(try draft(name: "API").validated(zone: "example.dev").name == "api.example.dev")
    }
    @Test func alreadyQualifiedNameIsKept() throws {
        #expect(try draft(name: "blog.example.dev").validated(zone: "example.dev").name == "blog.example.dev")
        #expect(try draft(name: "example.dev.").validated(zone: "example.dev").name == "example.dev")
    }
    @Test func aRecordRequiresIPv4() throws {
        #expect(try draft(content: "192.0.2.10").validated(zone: "example.dev").content == "192.0.2.10")
        #expect(throws: DNSValidationError.notIPv4) { try draft(content: "999.1.1.1").validated(zone: "example.dev") }
        #expect(throws: DNSValidationError.notIPv4) { try draft(content: "abc").validated(zone: "example.dev") }
    }
    @Test func aaaaRequiresIPv6() throws {
        #expect(try draft("AAAA", content: "2001:db8::1").validated(zone: "example.dev").type == "AAAA")
        #expect(throws: DNSValidationError.notIPv6) { try draft("AAAA", content: "192.0.2.10").validated(zone: "example.dev") }
    }
    @Test func cnameRequiresHostname() throws {
        #expect(try draft("CNAME", content: "workers.example.dev").validated(zone: "example.dev").content == "workers.example.dev")
        #expect(throws: DNSValidationError.notHostname) { try draft("CNAME", content: "not a host").validated(zone: "example.dev") }
    }
    @Test func mxRequiresPriority() throws {
        #expect(throws: DNSValidationError.missingPriority) { try draft("MX", name: "@", content: "mail.example.dev", proxied: false).validated(zone: "example.dev") }
        #expect(try draft("MX", name: "@", content: "mail.example.dev", proxied: false, priority: 10).validated(zone: "example.dev").priority == 10)
    }
    @Test func proxiedIsForcedFalseForMXAndTXT() throws {
        #expect(try draft("TXT", name: "@", content: "v=spf1 -all", proxied: true).validated(zone: "example.dev").proxied == false)
        #expect(try draft("MX", name: "@", content: "mail.example.dev", proxied: true, priority: 10).validated(zone: "example.dev").proxied == false)
        #expect(try draft("A", proxied: true).validated(zone: "example.dev").proxied == true)
    }
    @Test func emptyNameAndContentThrow() {
        #expect(throws: DNSValidationError.emptyName) { try draft(name: "  ").validated(zone: "example.dev") }
        #expect(throws: DNSValidationError.emptyContent) { try draft(content: "").validated(zone: "example.dev") }
    }
    @Test func errorCopyMatchesTheMockup() {
        #expect(DNSValidationError.notIPv4.errorDescription == "An A record needs an IPv4 address, such as 192.0.2.10.")
        #expect(DNSValidationError.emptyName.errorDescription == "Enter a name and content for the record.")
    }

    @Test func dnsRecordsMergesPagesOf100() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), page(of: req) == 1 ? list(["a", "b"], page: 1, totalPages: 2) : list(["c"], page: 2, totalPages: 2)) }
        let records = try await CFClient(token: "t", session: stub.session).dnsRecords(zoneID: "z1")
        #expect(records.map(\.id) == ["a", "b", "c"])
        let q = URLComponents(url: stub.recorded[0].request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(q?.first { $0.name == "per_page" }?.value == "100")
        #expect(stub.recorded[0].request.url?.path == "/client/v4/zones/z1/dns_records")
    }
    @Test func emptyZoneReturnsNoRecords() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), list([])) }
        #expect(try await CFClient(token: "t", session: stub.session).dnsRecords(zoneID: "z1").isEmpty)
    }
    @Test func createSendsValidatedBody() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), single("new1")) }
        let created = try await CFClient(token: "t", session: stub.session).createDNSRecord(zoneID: "z1", try draft().validated(zone: "example.dev"))
        #expect(created.id == "new1")
        let sent = try #require(stub.recorded.first)
        #expect(sent.request.httpMethod == "POST")
        let bodyData = try #require(sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["type"] as? String == "A")
        #expect(json["name"] as? String == "api.example.dev")
        #expect(json["content"] as? String == "192.0.2.10")
        #expect(json["proxied"] as? Bool == true)
        #expect(json["ttl"] as? Int == 1)
        #expect(json["priority"] == nil)
    }
    @Test func updateUsesPatch() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), single("r1")) }
        _ = try await CFClient(token: "t", session: stub.session).updateDNSRecord(zoneID: "z1", id: "r1", try draft().validated(zone: "example.dev"))
        #expect(stub.recorded[0].request.httpMethod == "PATCH")
        #expect(stub.recorded[0].request.url?.path == "/client/v4/zones/z1/dns_records/r1")
    }
    @Test func deleteUsesDelete() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"r1\"}}".utf8)) }
        try await CFClient(token: "t", session: stub.session).deleteDNSRecord(zoneID: "z1", id: "r1")
        #expect(stub.recorded[0].request.httpMethod == "DELETE")
        #expect(stub.recorded[0].request.url?.path == "/client/v4/zones/z1/dns_records/r1")
    }
}
