import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct ZoneSettingsTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func settingsKeepOnlyTheKnownStringOnes() async throws {
        let body = "{\"success\":true,\"errors\":[],\"result\":[{\"id\":\"ssl\",\"value\":\"full\",\"editable\":true},{\"id\":\"always_use_https\",\"value\":\"on\",\"editable\":false},{\"id\":\"minify\",\"value\":{\"css\":\"on\"},\"editable\":true},{\"id\":\"waf\",\"value\":\"off\"}]}"
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data(body.utf8)) }
        let s = try await client(stub).zoneSettings(zoneID: "z1")
        #expect(s.map(\.id) == ["ssl", "always_use_https"])
        #expect(s[0].value == "full" && s[0].editable && !s[1].editable)
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/zones/z1/settings")
    }

    @Test func updatePatchesOneSettingWithItsValue() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"ssl\",\"value\":\"strict\",\"editable\":true}}".utf8)) }
        let s = try await client(stub).updateZoneSetting(zoneID: "z1", id: "ssl", value: "strict")
        #expect(s.value == "strict")
        let r = try #require(stub.recorded.first)
        #expect(r.request.httpMethod == "PATCH" && r.request.url?.path == "/client/v4/zones/z1/settings/ssl")
        #expect(String(decoding: r.body ?? Data(), as: UTF8.self).contains("\"value\":\"strict\""))
    }

    @Test func purgeEverythingAndFilesSendTheRightBodies() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"p\"}}".utf8)) }
        let c = client(stub)
        try await c.purgeCache(zoneID: "z1", .everything)
        try await c.purgeCache(zoneID: "z1", .files(["https://a.dev/x.css"]))
        let b = stub.recorded.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        #expect(b[0].contains("\"purge_everything\":true") && b[1].contains("\"files\":[\"https:\\/\\/a.dev\\/x.css\"]"))
        #expect(stub.recorded[0].request.url?.path == "/client/v4/zones/z1/purge_cache" && stub.recorded[0].request.httpMethod == "POST")
    }

    @Test func purgeUrlsAreValidatedAndCapped() {
        #expect(PurgeURLs.parse((0..<100).map { "https://a.dev/\($0)" }.joined(separator: "\n")).isSuccess)
        #expect(PurgeURLs.parse("https://a.dev/x\n  https://a.dev/y  \n\n") == .success(["https://a.dev/x", "https://a.dev/y"]))
        #expect(PurgeURLs.parse("   ") == .failure(.empty))
        #expect(PurgeURLs.parse("a.dev/x") == .failure(.notURL("a.dev/x")))
        #expect(PurgeURLs.parse((0..<101).map { "https://a.dev/\($0)" }.joined(separator: "\n")) == .failure(.tooMany))
    }
}

private extension Result { var isSuccess: Bool { if case .success = self { true } else { false } } }
