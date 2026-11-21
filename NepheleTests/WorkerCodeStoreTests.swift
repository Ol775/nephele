import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkerCodeStoreTests {
    nonisolated static let binary = Data([0x00, 0xFF, 0x80, 0x01])
    nonisolated static let version = "{\"id\":\"v-new\",\"number\":3,\"metadata\":{\"created_on\":\"2026-11-19T10:00:00Z\"}}"

    nonisolated static func content(mainBinary: Bool = false) -> (String, Data) {
        var form = MultipartForm(boundary: "B")
        if mainBinary { form.addFile(name: "index.js", filename: "index.js", contentType: "application/wasm", data: binary) }
        else { form.addFile(name: "index.js", filename: "index.js", contentType: "application/javascript+module", data: Data("export default {}".utf8)) }
        form.addFile(name: "lib/util.js", filename: "lib/util.js", contentType: "application/javascript+module", data: Data("export const a = 1".utf8))
        form.addFile(name: "blob.wasm", filename: "blob.wasm", contentType: "application/wasm", data: binary)
        return (form.contentType, form.body)
    }

    func make(mainBinary: Bool = false) async throws -> (WorkerStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if p.hasSuffix("/content/v2") {
                let (type, body) = Self.content(mainBinary: mainBinary)
                return (StubURLProtocol.response(req.url!, headers: ["Content-Type": type, "CF-Entrypoint": "index.js"]), body)
            }
            if req.httpMethod == "POST" && p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok(Self.version)) }
            if p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok("{\"items\":[]}")) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok("{\"deployments\":[]}")) }
            if p.hasSuffix("/settings") { return TestAPI.reply(req, TestAPI.ok(WorkerSettingsStoreTests.settings)) }
            if p.hasSuffix("/secrets") { return TestAPI.reply(req, TestAPI.ok("[]")) }
            if p.hasSuffix("/subdomain") { return TestAPI.reply(req, TestAPI.ok("{\"enabled\":false}")) }
            return TestAPI.base(req)
        }
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: try await TestAPI.readySession(stub))
        await store.loadCode()
        return (store, stub)
    }

    func uploaded(_ stub: StubServer) throws -> [MultipartPart] {
        let rec = try #require(stub.recorded.first { $0.request.httpMethod == "POST" })
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        return MultipartForm.parse(raw, contentType: type)
    }

    @Test func loadPutsMainModuleInTheDraftAndListsTheRest() async throws {
        let (store, _) = try await make()
        #expect(store.draft == "export default {}")
        #expect(store.extraModules.map(\.name) == ["lib/util.js", "blob.wasm"])
        #expect(store.hasUnsavedChanges == false)
        #expect(store.readOnlyReason == nil)
    }

    @Test func unsavedGuardTracksDraftVersusLoaded() async throws {
        let (store, _) = try await make()
        store.draft += "\n// edit"
        #expect(store.hasUnsavedChanges)
        store.draft = "export default {}"
        #expect(store.hasUnsavedChanges == false)
    }

    @Test func saveWithEmptyMessageShowsErrorAndSendsNothing() async throws {
        let (store, stub) = try await make()
        store.draft = "export default { a: 1 }"
        await store.saveVersion(message: "   ")
        #expect(store.formError != nil)
        #expect(stub.recorded.filter { $0.request.httpMethod == "POST" }.isEmpty)
        #expect(store.hasUnsavedChanges)
    }

    @Test func saveReplacesOnlyMainModuleText() async throws {
        let (store, stub) = try await make()
        store.draft = "export default { a: 1 }"
        await store.saveVersion(message: "Edit")
        let parts = try uploaded(stub)
        #expect(parts.first { $0.name == "index.js" }?.data == Data("export default { a: 1 }".utf8))
        #expect(parts.first { $0.name == "lib/util.js" }?.data == Data("export const a = 1".utf8))
        #expect(parts.first { $0.name == "blob.wasm" }?.data == Self.binary)
        #expect(store.hasUnsavedChanges == false)
        #expect(store.lastSavedVersionID == "v-new")
    }

    @Test func saveDoesNotDeploy() async throws {
        let (store, stub) = try await make()
        store.draft = "export default { a: 1 }"
        await store.saveVersion(message: "Edit")
        #expect(!stub.recorded.contains { $0.request.httpMethod == "POST" && $0.request.url!.path.hasSuffix("/deployments") })
    }

    @Test func nonUTF8MainModuleIsReadOnlyWithExplanation() async throws {
        let (store, stub) = try await make(mainBinary: true)
        #expect(store.readOnlyReason != nil)
        await store.saveVersion(message: "Edit")
        #expect(stub.recorded.filter { $0.request.httpMethod == "POST" }.isEmpty)
    }
}
