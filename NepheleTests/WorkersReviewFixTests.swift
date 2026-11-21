import Testing
import Foundation
import AppKit
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

/// Regression tests for the final review's Critical and Important findings.
@MainActor
@Suite struct WorkersReviewFixTests {
    final class Box: @unchecked Sendable {
        private let lock = NSLock(); private var _secret = false
        var secretAdded: Bool { get { lock.withLock { _secret } } set { lock.withLock { _secret = newValue } } }
    }

    nonisolated static func settingsJSON(secret: Bool) -> String {
        let extra = secret ? ",{\"name\":\"DB_PASSWORD\",\"type\":\"secret_text\"}" : ""
        return "{\"compatibility_date\":\"2026-10-01\",\"compatibility_flags\":[],\"observability\":{\"enabled\":false},\"bindings\":[{\"name\":\"KV\",\"type\":\"kv_namespace\",\"namespace_id\":\"ns_1\"},{\"name\":\"API_KEY\",\"type\":\"secret_text\"}\(extra)]}"
    }

    func make(box: Box = Box(), secretsGetStatus: Int = 200, routePostStatus: Int = 200, accountID: String? = nil) async throws -> (WorkerStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if req.httpMethod == "PUT" && p.hasSuffix("/secrets") { box.secretAdded = true; return TestAPI.reply(req, TestAPI.ok("{}")) }
            if req.httpMethod == "GET" && p.hasSuffix("/secrets") {
                return secretsGetStatus == 200 ? TestAPI.reply(req, TestAPI.ok("[{\"name\":\"API_KEY\"}]")) : TestAPI.reply(req, TestAPI.forbiddenBody, status: secretsGetStatus)
            }
            if p.hasSuffix("/workers/routes") && req.httpMethod == "POST" { return TestAPI.reply(req, routePostStatus == 200 ? TestAPI.ok("{}") : TestAPI.forbiddenBody, status: routePostStatus) }
            if p.hasSuffix("/workers/routes") { return TestAPI.reply(req, TestAPI.ok("[]")) }
            if p.hasSuffix("/schedules") { return TestAPI.reply(req, TestAPI.ok("{\"schedules\":[]}")) }
            if p.hasSuffix("/settings") { return TestAPI.reply(req, TestAPI.ok(Self.settingsJSON(secret: box.secretAdded))) }
            if p.hasSuffix("/subdomain") { return TestAPI.reply(req, TestAPI.ok("{\"enabled\":false}")) }
            if p.hasSuffix("/content/v2") {
                var form = MultipartForm(boundary: "B")
                form.addFile(name: "index.js", filename: "index.js", contentType: "application/javascript+module", data: Data("export default {}".utf8))
                return (StubURLProtocol.response(req.url!, headers: ["Content-Type": form.contentType, "CF-Entrypoint": "index.js"]), form.body)
            }
            if req.httpMethod == "POST" && p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"v1\",\"number\":1}")) }
            if p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok("{\"items\":[]}")) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok("{\"deployments\":[]}")) }
            if req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.ok("{}")) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: session, accountID: accountID)
        await store.loadSettings()
        return (store, stub)
    }

    func patches(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod == "PATCH" } }
    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    func bindings(of rec: StubServer.Recorded) throws -> [JSONValue] {
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        let part = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "settings" })
        guard case .array(let list)? = try JSONDecoder().decode(JSONValue.self, from: part.data)["bindings"] else { return [] }
        return list
    }

    // C1
    @Test func aSecretSetThisSessionSurvivesALaterVariableSave() async throws {
        let (store, stub) = try await make()
        await store.setSecret(name: "DB_PASSWORD", value: "v")
        await store.setVar(name: "EXTRA", value: "1")
        let sent = try bindings(of: try #require(patches(stub).last))
        #expect(sent.contains { $0["name"] == .string("DB_PASSWORD") && $0["type"] == .string("inherit") })
    }

    @Test func aCodeSaveAfterANewSecretKeepsSecretBindings() async throws {
        let (store, stub) = try await make()
        await store.loadCode()
        await store.setSecret(name: "DB_PASSWORD", value: "v")
        store.draft = "export default { a: 1 }"
        await store.saveVersion(message: "Edit")
        let rec = try #require(writes(stub).last { $0.request.url!.path.hasSuffix("/versions") })
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        let meta = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "metadata" })
        let json = try JSONDecoder().decode(JSONValue.self, from: meta.data)
        #expect(json["keep_bindings"] == .array([.string("kv_namespace"), .string("secret_text")]))
    }

    // C2
    @Test func aStoreFromAnotherAccountRefusesWritesAndLoads() async throws {
        let (store, stub) = try await make(accountID: "accOLD")
        #expect(store.settings.value == nil)
        let before = stub.recorded.count
        await store.setVar(name: "EXTRA", value: "1")
        await store.setSecret(name: "S", value: "v")
        #expect(store.formError?.contains("account") == true)
        #expect(stub.recorded.count == before)
    }

    // I1
    @Test func reloadingTheCodeTabKeepsUnsavedEdits() async throws {
        let (store, _) = try await make()
        await store.loadCode()
        store.draft = "my edit"
        await store.loadCode()
        #expect(store.draft == "my edit")
        #expect(store.hasUnsavedChanges)
    }

    // I2
    @Test func addingAVariableNeverReplacesASecretOrOtherBinding() async throws {
        let (store, stub) = try await make()
        await store.setVar(name: "API_KEY", value: "x")
        #expect(store.formError != nil)
        store.formError = nil
        await store.setVar(name: "KV", value: "x")
        #expect(store.formError != nil)
        #expect(writes(stub).isEmpty)
    }

    // I3
    @Test func aForbiddenRouteWriteDoesNotTurnOffScriptWrites() async throws {
        let (store, _) = try await make(routePostStatus: 403)
        await store.loadTriggers(zones: [TestAPI.zone])
        await store.addRoute(pattern: "api.example.dev/*", zone: TestAPI.zone)
        #expect(store.canWrite)
        #expect(store.formError?.contains("Workers Routes") == true)
    }

    @Test func aFailedFollowUpReadAfterSetSecretDoesNotTurnOffWrites() async throws {
        let (store, stub) = try await make(secretsGetStatus: 403)
        await store.setSecret(name: "DB_PASSWORD", value: "v")
        #expect(store.canWrite)
        #expect(writes(stub).filter { $0.request.httpMethod == "PUT" }.count == 1)
    }

    // I4
    @Test func triggersOnlyReadZonesOfThisAccount() async throws {
        let (store, stub) = try await make()
        let other = Zone(id: "zB", name: "other.dev", status: "active", planName: "Free", accountID: "accB")
        await store.loadTriggers(zones: [TestAPI.zone, other])
        let routeReads = stub.recorded.filter { $0.request.url!.path.hasSuffix("/workers/routes") }.map { $0.request.url!.path }
        #expect(routeReads == ["/client/v4/zones/z1/workers/routes"])
    }

    // I5
    @Test func aListLoadStartedBeforeASignOutIsDropped() async throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let armed = Box()   // reuses the flag: true once sign-in is done
        let stub = StubServer { req in
            if armed.secretAdded && req.url!.path.hasSuffix("/workers/scripts") {
                entered.signal(); release.wait()
                return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"old-account-worker\"}]"))
            }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        armed.secretAdded = true
        let store = WorkersStore(session: session)
        let load = Task { await store.load() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.global().async { entered.wait(); c.resume() } }
        session.selectAccount("accB"); store.reset()
        release.signal()
        await load.value
        #expect(store.workers.value == nil)
    }

    // I6
    @Test func theCodeEditorTurnsOffSmartSubstitutions() {
        let tv = NSTextView()
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        CodeEditor.configure(tv)
        #expect(!tv.isAutomaticQuoteSubstitutionEnabled && !tv.isAutomaticDashSubstitutionEnabled && !tv.isAutomaticTextReplacementEnabled)
        #expect(!tv.isAutomaticSpellingCorrectionEnabled && !tv.isRichText)
    }
}
