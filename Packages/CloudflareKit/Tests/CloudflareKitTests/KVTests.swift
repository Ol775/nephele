import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct KVTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func namespacesDecode() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("kv-namespaces")) }
        let list = try await client(stub).kvNamespaces(accountID: "acc1")
        #expect(list.map(\.title) == ["CACHE", "SESSIONS"])
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/storage/kv/namespaces")
    }

    @Test func createSendsTitleAndReturnsNamespace() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"ns9\",\"title\":\"NEW\"}}".utf8)) }
        let ns = try await client(stub).createKVNamespace(accountID: "acc1", title: "NEW")
        #expect(ns == KVNamespace(id: "ns9", title: "NEW"))
        let raw = try #require(stub.recorded.first?.body)
        #expect(try JSONDecoder().decode(JSONValue.self, from: raw)["title"] == .string("NEW"))
    }

    @Test func keysDecodeWithCursorAndSendPrefix() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("kv-keys")) }
        let page = try await client(stub).kvKeys(accountID: "acc1", namespace: "ns1", prefix: "user:", cursor: "C0", limit: 50)
        #expect(page.keys.map(\.name) == ["user:1", "user:2"])
        #expect(page.keys[0].expiration == 1_900_000_000)
        #expect(page.nextCursor == "CUR1")
        let q = stub.recorded.first?.request.url?.query ?? ""
        #expect(q.contains("prefix=user:") && q.contains("cursor=C0") && q.contains("limit=50"))
    }

    @Test func lastPageHasNoCursor() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":[],\"result_info\":{\"count\":0,\"cursor\":\"\"}}".utf8)) }
        #expect(try await client(stub).kvKeys(accountID: "a", namespace: "n").nextCursor == nil)
    }

    @Test func keyNamesAreEncodedIncludingSlashesAndSpaces() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("hello".utf8)) }
        let data = try await client(stub).kvValue(accountID: "acc1", namespace: "ns1", key: "a b/c")
        #expect(String(data: data, encoding: .utf8) == "hello")
        #expect(stub.recorded.first?.request.url?.absoluteString.hasSuffix("/values/a%20b%2Fc") == true)
    }

    @Test func putSendsRawBytesAsOctetStream() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).putKVValue(accountID: "acc1", namespace: "ns1", key: "k", value: Data("v1".utf8))
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "PUT")
        #expect(rec.request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(rec.body == Data("v1".utf8))
    }

    @Test func deleteKeyAndNamespaceUseDelete() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteKVKey(accountID: "acc1", namespace: "ns1", key: "k")
        try await client(stub).deleteKVNamespace(accountID: "acc1", namespace: "ns1")
        #expect(stub.recorded.map { $0.request.httpMethod } == ["DELETE", "DELETE"])
        #expect(stub.recorded[1].request.url?.path == "/client/v4/accounts/acc1/storage/kv/namespaces/ns1")
    }

    @Test func dotSegmentsAreEncodedSoAKeyCannotClimbToTheNamespace() async throws {
        #expect(pathSegment("..") == "%2E%2E")
        #expect(pathSegment(".") == "%2E")
        #expect(pathSegment("a.b") == "a.b")
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteKVKey(accountID: "acc1", namespace: "ns1", key: "..")
        #expect(stub.recorded.first?.request.url?.absoluteString.hasSuffix("/values/%2E%2E") == true)
    }

    @Test func putKeepsTheExpirationWhenGiven() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).putKVValue(accountID: "a", namespace: "n", key: "k", value: Data("v".utf8), expiration: 1_900_000_000)
        #expect(stub.recorded.first?.request.url?.query?.contains("expiration=1900000000") == true)
        try await client(stub).putKVValue(accountID: "a", namespace: "n", key: "k", value: Data("v".utf8))
        #expect(stub.recorded.last?.request.url?.query == nil)
    }

    @Test func keysCarryMetadata() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"a\",\"metadata\":{\"x\":1}},{\"name\":\"b\"}],\"result_info\":{\"count\":2,\"cursor\":\"\"}}".utf8)) }
        let page = try await client(stub).kvKeys(accountID: "a", namespace: "n")
        #expect(page.keys[0].metadata != nil && page.keys[1].metadata == nil)
    }

    @Test func anUnencodedPathThrowsInsteadOfCrashing() async {
        let stub = StubServer()
        let c = client(stub)
        await #expect(throws: CloudflareError.transport("Invalid request path")) { _ = try await c.kvValue(accountID: "a b", namespace: "n", key: "k") }
        await #expect(throws: CloudflareError.transport("Invalid request path")) { _ = try await c.kvValue(accountID: "é", namespace: "n", key: "k") }
        #expect(stub.recorded.isEmpty)
    }
}
