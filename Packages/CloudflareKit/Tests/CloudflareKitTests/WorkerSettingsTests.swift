import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerSettingsTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    let ok = Data("{\"success\":true,\"errors\":[],\"result\":{}}".utf8)

    func settingsPart(_ stub: StubServer, index: Int = 0) throws -> [String: JSONValue] {
        let rec = stub.recorded[index]
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        let part = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "settings" })
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: part.data) else { throw CloudflareError.decoding("x") }
        return o
    }

    @Test func settingsDecodePreservesBindingFieldsExactly() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-settings")) }
        let s = try await client(stub).workerSettings(accountID: "acc1", script: "hello-api")
        #expect(s.compatibilityDate == "2026-10-01")
        #expect(s.compatibilityFlags == ["nodejs_compat"])
        #expect(s.observabilityEnabled)
        #expect(s.bindings.map(\.name) == ["KV", "GREETING", "API_KEY"])
        #expect(s.bindings[0].fields["namespace_id"] == .string("ns_1"))
        #expect(s.plainVars.map(\.name) == ["GREETING"])
        #expect(s.plainVars[0].text == "hi")
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        #expect(String(data: try enc.encode(s.bindings[0]), encoding: .utf8) == "{\"name\":\"KV\",\"namespace_id\":\"ns_1\",\"type\":\"kv_namespace\"}")
    }

    @Test func updateOmitsNilFieldsAndUsesMultipartSettingsPart() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-settings")) }
        _ = try await client(stub).updateWorkerSettings(accountID: "acc1", script: "hello-api", WorkerSettingsChange(compatibilityDate: "2026-11-01"))
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "PATCH")
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/settings")
        let o = try settingsPart(stub)
        #expect(o["compatibility_date"] == .string("2026-11-01"))
        #expect(o["bindings"] == nil && o["compatibility_flags"] == nil && o["observability"] == nil)
    }

    @Test func updateSendsSecretBindingsAsInheritSoTheyAreKept() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-settings")) }
        let current = try await client(stub).workerSettings(accountID: "acc1", script: "hello-api")
        _ = try await client(stub).updateWorkerSettings(accountID: "acc1", script: "hello-api", WorkerSettingsChange(bindings: current.bindings))
        let sent = try settingsPart(stub, index: 1)
        guard case .array(let list)? = sent["bindings"] else { Issue.record("no bindings"); return }
        #expect(list.count == 3)
        #expect(list[0]["namespace_id"] == .string("ns_1"))
        #expect(list[2] == .object(["name": .string("API_KEY"), "type": .string("inherit")]))
    }

    @Test func secretNamesNeverContainValues() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-secrets")) }
        let names = try await client(stub).workerSecretNames(accountID: "acc1", script: "hello-api")
        #expect(names == ["API_KEY", "DB_PASSWORD"])
    }

    @Test func setSecretSendsValueOnlyInBody() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"name\":\"API_KEY\",\"type\":\"secret_text\"}}".utf8)) }
        try await client(stub).setWorkerSecret(accountID: "acc1", script: "hello-api", name: "API_KEY", value: "s3cret-value")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "PUT")
        #expect(rec.request.url?.absoluteString.contains("s3cret") == false)
        let raw = try #require(rec.body)
        let body = try JSONDecoder().decode(JSONValue.self, from: raw)
        #expect(body["text"] == .string("s3cret-value"))
        #expect(body["type"] == .string("secret_text"))
        #expect(body["name"] == .string("API_KEY"))
    }

    @Test func deleteSecretUsesDeleteOnNamedPath() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteWorkerSecret(accountID: "acc1", script: "hello-api", name: "API_KEY")
        #expect(stub.recorded.first?.request.httpMethod == "DELETE")
        #expect(stub.recorded.first?.request.url?.path.hasSuffix("/secrets/API_KEY") == true)
    }

    @Test func workersDevSubdomainReadAndToggle() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"enabled\":true,\"previews_enabled\":false}}".utf8)) }
        #expect(try await client(stub).workersDevSubdomain(accountID: "acc1", script: "hello-api") == true)
        try await client(stub).setWorkersDevSubdomain(accountID: "acc1", script: "hello-api", enabled: false)
        let rec = try #require(stub.recorded.last)
        #expect(rec.request.httpMethod == "POST")
        let raw = try #require(rec.body)
        #expect(try JSONDecoder().decode(JSONValue.self, from: raw)["enabled"] == .bool(false))
    }

    @Test func validBindingNames() {
        #expect(validBindingName("API_KEY") && validBindingName("$x") && validBindingName("a1"))
        #expect(!validBindingName("1a") && !validBindingName("") && !validBindingName("has space") && !validBindingName("a-b"))
    }

    @Test func validWorkerNameRules() {
        #expect(validWorkerName("hello-api") && validWorkerName("a") && validWorkerName("a1-b2"))
        #expect(!validWorkerName("-a") && !validWorkerName("a-") && !validWorkerName("A") && !validWorkerName(""))
        #expect(!validWorkerName(String(repeating: "a", count: 64)) && validWorkerName(String(repeating: "a", count: 63)))
        #expect(!validWorkerName("a_b") && !validWorkerName("a b"))
    }
}
