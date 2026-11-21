import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct TransportTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "tok_SECRET123", session: stub.session) }

    @Test func jsonValueRoundTripsUnknownKeysExactly() throws {
        let src = Data("{\"my_var\":{\"nested_key\":[1,\"a\",null,true]}}".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: src)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let out = try enc.encode(value)
        #expect(String(data: out, encoding: .utf8) == "{\"my_var\":{\"nested_key\":[1,\"a\",null,true]}}")
        #expect(value["my_var"]?["nested_key"] != nil)
    }

    @Test func rawReturnsBodyBytesAndKeepsSnakeCaseKeys() async throws {
        let payload = "{\"success\":true,\"errors\":[],\"result\":{\"namespace_id\":\"abc\"}}"
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data(payload.utf8)) }
        let data = try await client(stub).raw("GET", "/things")
        #expect(String(data: data, encoding: .utf8) == payload)
    }

    @Test func rawSendsBodyAndContentType() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{}}".utf8)) }
        _ = try await client(stub).raw("POST", "/things", body: Data("x".utf8), contentType: "multipart/form-data; boundary=B")
        let sent = try #require(stub.recorded.first)
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        #expect(sent.body == Data("x".utf8))
    }

    @Test func rawThrowsPermissionDeniedOn403WithEnvelopeMessage() async {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!, status: 403), Data("{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}".utf8))
        }
        let c = client(stub)
        await #expect(throws: CloudflareError.permissionDenied("Authentication error")) { _ = try await c.raw("GET", "/things") }
    }

    @Test func downloadReturnsBytesAndLowercasedHeaders() async throws {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!, headers: ["CF-Entrypoint": "index.js"]), Data("export default {}".utf8))
        }
        let out = try await client(stub).download("/script")
        #expect(String(data: out.data, encoding: .utf8) == "export default {}")
        #expect(out.headers["cf-entrypoint"] == "index.js")
    }

    @Test func downloadMapsForbiddenToPermissionDenied() async {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!, status: 403), Data("{}".utf8)) }
        let c = client(stub)
        await #expect(throws: CloudflareError.permissionDenied(nil)) { _ = try await c.download("/script") }
    }

    @Test func multipartBuildsPartsWithBoundaryAndContentType() throws {
        var form = MultipartForm(boundary: "BOUND")
        form.addJSON(name: "metadata", Data("{\"main_module\":\"index.js\"}".utf8))
        form.addFile(name: "index.js", filename: "index.js", contentType: "application/javascript+module", data: Data("export default {}".utf8))
        #expect(form.contentType == "multipart/form-data; boundary=BOUND")
        let text = String(data: form.body, encoding: .utf8) ?? ""
        #expect(text.contains("--BOUND\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"metadata\""))
        #expect(text.contains("filename=\"index.js\""))
        #expect(text.hasSuffix("--BOUND--\r\n"))
    }

    @Test func multipartParseRoundTripsTwoFilesIncludingBinaryBytes() throws {
        var form = MultipartForm(boundary: "BOUND")
        let binary = Data([0x00, 0xFF, 0x0D, 0x0A, 0x2D, 0x2D, 0x80])
        form.addFile(name: "index.js", filename: "index.js", contentType: "application/javascript+module", data: Data("export default {}".utf8))
        form.addFile(name: "blob.wasm", filename: "blob.wasm", contentType: "application/wasm", data: binary)
        let parts = MultipartForm.parse(form.body, contentType: form.contentType)
        #expect(parts.count == 2)
        #expect(parts[0].filename == "index.js")
        #expect(parts[0].contentType == "application/javascript+module")
        #expect(parts[0].data == Data("export default {}".utf8))
        #expect(parts[1].name == "blob.wasm")
        #expect(parts[1].data == binary)
    }
}
