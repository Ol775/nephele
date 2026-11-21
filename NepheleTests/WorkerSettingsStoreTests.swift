import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkerSettingsStoreTests {
    nonisolated static let settings = "{\"compatibility_date\":\"2026-10-01\",\"compatibility_flags\":[\"nodejs_compat\"],\"observability\":{\"enabled\":false},\"bindings\":[{\"name\":\"KV\",\"type\":\"kv_namespace\",\"namespace_id\":\"ns_1\"},{\"name\":\"GREETING\",\"type\":\"plain_text\",\"text\":\"hi\"},{\"name\":\"API_KEY\",\"type\":\"secret_text\"}]}"

    func make(denyWrites: Bool = false) async throws -> (WorkerStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if p.hasSuffix("/settings") { return TestAPI.reply(req, TestAPI.ok(Self.settings)) }
            if p.hasSuffix("/secrets") && req.httpMethod == "GET" { return TestAPI.reply(req, TestAPI.ok("[{\"name\":\"API_KEY\",\"type\":\"secret_text\"}]")) }
            if p.contains("/secrets") { return TestAPI.reply(req, TestAPI.ok("{}")) }
            if p.hasSuffix("/subdomain") { return TestAPI.reply(req, TestAPI.ok("{\"enabled\":true,\"previews_enabled\":false}")) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: session)
        await store.loadSettings()
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    func sentBindings(_ rec: StubServer.Recorded) throws -> [JSONValue] {
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        let part = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "settings" })
        let json = try JSONDecoder().decode(JSONValue.self, from: part.data)
        guard case .array(let list)? = json["bindings"] else { Issue.record("no bindings sent"); return [] }
        return list
    }

    @Test func loadsSettingsSecretsAndWorkersDev() async throws {
        let (store, _) = try await make()
        #expect(store.settings.value?.plainVars.map(\.name) == ["GREETING"])
        #expect(store.secretNames.value == ["API_KEY"])
        #expect(store.workersDev == true)
    }

    @Test func setVarWithInvalidNameShowsErrorWithoutRequest() async throws {
        let (store, stub) = try await make()
        await store.setVar(name: "1bad name", value: "x")
        #expect(store.formError != nil)
        #expect(writes(stub).isEmpty)
    }

    @Test func settingsPatchKeepsOtherBindingsUnchanged() async throws {
        let (store, stub) = try await make()
        await store.setVar(name: "GREETING", value: "hello")
        let sent = try sentBindings(try #require(writes(stub).first))
        #expect(sent.count == 3)
        #expect(sent.contains { $0["namespace_id"] == .string("ns_1") })
        #expect(sent.contains { $0["name"] == .string("API_KEY") && $0["type"] == .string("inherit") })
        #expect(sent.contains { $0["name"] == .string("GREETING") && $0["text"] == .string("hello") })
    }

    @Test func forbiddenWriteDisablesControlsAndShowsEditHint() async throws {
        let (store, _) = try await make(denyWrites: true)
        await store.setVar(name: "NEW", value: "x")
        #expect(store.canWrite == false)
        #expect(store.formError?.contains("Workers Scripts Edit") == true)
    }

    @Test func removeVarRequiresConfirmationNamingWorkerAndVar() async throws {
        let (store, stub) = try await make()
        store.requestChange(.removeVar("GREETING"))
        let pending = try #require(store.confirm.pending)
        #expect(pending.message(worker: "hello-api").contains("hello-api"))
        #expect(pending.message(worker: "hello-api").contains("GREETING"))
        #expect(writes(stub).isEmpty)
        await store.confirmChange(pending)
        await store.confirmChange(pending)
        #expect(writes(stub).count == 1)
        #expect(try sentBindings(try #require(writes(stub).first)).count == 2)
    }

    @Test func deleteSecretNeedsConfirmationThenSendsOnce() async throws {
        let (store, stub) = try await make()
        store.requestChange(.deleteSecret("API_KEY"))
        #expect(writes(stub).isEmpty)
        await store.confirmChange(.deleteSecret("API_KEY"))
        #expect(writes(stub).filter { $0.request.httpMethod == "DELETE" }.count == 1)
    }

    @Test func workersDevToggleIsConfirmed() async throws {
        let (store, stub) = try await make()
        store.requestChange(.toggleWorkersDev(false))
        #expect(writes(stub).isEmpty)
        await store.confirmChange(.toggleWorkersDev(false))
        #expect(store.workersDev == false)
        #expect(writes(stub).count == 1)
    }

    @Test func secretValueIsNotInStateErrorsOrDescriptionAfterSend() async throws {
        let sentinel = "SENTINEL-s3cret-value-123"
        let (store, _) = try await make()
        await store.setSecret(name: "DB_PASSWORD", value: sentinel)
        let dump = String(describing: store.settings) + String(describing: store.secretNames) + (store.formError ?? "") + String(describing: store.confirm.pending)
        #expect(!dump.contains(sentinel))
        let (denied, _) = try await make(denyWrites: true)
        await denied.setSecret(name: "DB_PASSWORD", value: sentinel)
        #expect(!(denied.formError ?? "").contains(sentinel))
    }

    @Test func settingsToggleSendsOnlyThatField() async throws {
        let (store, stub) = try await make()
        await store.saveSettings(WorkerSettingsChange(observabilityEnabled: true))
        let rec = try #require(writes(stub).first)
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        let part = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "settings" })
        let json = try JSONDecoder().decode(JSONValue.self, from: part.data)
        #expect(json["observability"]?["enabled"] == .bool(true))
        #expect(json["bindings"] == nil)
    }
}
