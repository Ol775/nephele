import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerCodeTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    static let binary = Data([0x00, 0xFF, 0x0D, 0x0A, 0x2D, 0x2D, 0x80, 0x01])

    func multipartResponse(_ req: URLRequest) -> (HTTPURLResponse, Data) {
        var form = MultipartForm(boundary: "BOUND")
        form.addFile(name: "index.js", filename: "index.js", contentType: "application/javascript+module", data: Data("export default {}".utf8))
        form.addFile(name: "lib/util.js", filename: "lib/util.js", contentType: "application/javascript+module", data: Data("export const a = 1".utf8))
        form.addFile(name: "blob.wasm", filename: "blob.wasm", contentType: "application/wasm", data: Self.binary)
        return (StubURLProtocol.response(req.url!, headers: ["Content-Type": form.contentType, "CF-Entrypoint": "index.js"]), form.body)
    }

    let settings = WorkerSettings(compatibilityDate: "2026-10-01", compatibilityFlags: ["nodejs_compat"], observabilityEnabled: true, bindings: [
        WorkerBinding(fields: ["name": .string("KV"), "type": .string("kv_namespace"), "namespace_id": .string("ns")]),
        WorkerBinding.plain(name: "A", text: "1"),
        WorkerBinding(fields: ["name": .string("S"), "type": .string("secret_text")]),
    ])
    let versionOK = Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"v-new\",\"number\":3,\"metadata\":{\"created_on\":\"2026-11-19T10:00:00Z\"}}}".utf8)

    func uploadedParts(_ stub: StubServer) throws -> [MultipartPart] {
        let rec = try #require(stub.recorded.first)
        let type = try #require(rec.request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(rec.body)
        return MultipartForm.parse(raw, contentType: type)
    }

    func metadata(_ parts: [MultipartPart]) throws -> JSONValue {
        let part = try #require(parts.first { $0.name == "metadata" })
        return try JSONDecoder().decode(JSONValue.self, from: part.data)
    }

    @Test func workerCodeParsesEntrypointAndExtraModules() async throws {
        let stub = StubServer { req in multipartResponse(req) }
        let code = try await client(stub).workerCode(accountID: "acc1", script: "hello-api")
        #expect(code.mainModule == "index.js")
        #expect(code.modules.map(\.name) == ["index.js", "lib/util.js", "blob.wasm"])
        #expect(code.modules[0].text == "export default {}")
        #expect(code.modules[2].text == nil)
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/content/v2")
    }

    @Test func workerCodeFallsBackToSingleScriptBody() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!, headers: ["Content-Type": "application/javascript"]), Data("addEventListener('fetch', () => {})".utf8)) }
        let code = try await client(stub).workerCode(accountID: "acc1", script: "old")
        #expect(code.modules.count == 1)
        #expect(code.modules[0].text == "addEventListener('fetch', () => {})")
        #expect(code.mainModule == code.modules[0].name)
    }

    @Test func uploadVersionResendsUntouchedModulesByteForByteAndBinarySurvives() async throws {
        let fetch = StubServer { req in multipartResponse(req) }
        var code = try await client(fetch).workerCode(accountID: "acc1", script: "s")
        code.modules[0] = WorkerModule(name: "index.js", contentType: "application/javascript+module", data: Data("export default { new: 1 }".utf8))
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), versionOK) }
        let v = try await client(stub).uploadVersion(accountID: "acc1", script: "s", code: code, settings: settings, message: "Edit")
        #expect(v.id == "v-new" && v.number == 3)
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "POST")
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/s/versions")
        let parts = try uploadedParts(stub)
        #expect(parts.first { $0.name == "index.js" }?.data == Data("export default { new: 1 }".utf8))
        #expect(parts.first { $0.name == "lib/util.js" }?.data == Data("export const a = 1".utf8))
        #expect(parts.first { $0.name == "blob.wasm" }?.data == Self.binary)
        #expect(parts.first { $0.name == "blob.wasm" }?.contentType == "application/wasm")
    }

    @Test func uploadVersionSetsKeepBindingsForEveryExistingBindingType() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), versionOK) }
        let code = WorkerCode(mainModule: "index.js", modules: [WorkerModule(name: "index.js", contentType: "application/javascript+module", data: Data("x".utf8))])
        _ = try await client(stub).uploadVersion(accountID: "acc1", script: "s", code: code, settings: settings, message: "Edit")
        let meta = try metadata(try uploadedParts(stub))
        #expect(meta["main_module"] == .string("index.js"))
        #expect(meta["compatibility_date"] == .string("2026-10-01"))
        #expect(meta["compatibility_flags"] == .array([.string("nodejs_compat")]))
        guard case .array(let keep)? = meta["keep_bindings"] else { Issue.record("no keep_bindings"); return }
        #expect(Set(keep) == [.string("kv_namespace"), .string("plain_text"), .string("secret_text")])
    }

    @Test func uploadVersionPutsMessageInAnnotations() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), versionOK) }
        let code = WorkerCode(mainModule: "index.js", modules: [WorkerModule(name: "index.js", contentType: "application/javascript+module", data: Data("x".utf8))])
        _ = try await client(stub).uploadVersion(accountID: "acc1", script: "s", code: code, settings: settings, message: "Fixed it")
        #expect(try metadata(try uploadedParts(stub))["annotations"]?["workers/message"] == .string("Fixed it"))
    }

    @Test func uploadVersionRequiresAMessageBeforeSending() async {
        let stub = StubServer()
        let code = WorkerCode(mainModule: "index.js", modules: [WorkerModule(name: "index.js", contentType: "application/javascript+module", data: Data("x".utf8))])
        let c = client(stub)
        let s = settings
        await #expect(throws: WorkerValidationError.messageRequired) { _ = try await c.uploadVersion(accountID: "a", script: "s", code: code, settings: s, message: "  ") }
        #expect(stub.recorded.isEmpty)
    }
}
