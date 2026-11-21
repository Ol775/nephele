import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct R2Tests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func bucketsDecodeFromTheNestedList() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("r2-buckets")) }
        let list = try await client(stub).r2Buckets(accountID: "acc1")
        #expect(list.map(\.name) == ["media", "backups"])
        #expect(list[0].location == "weur")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/r2/buckets")
    }

    @Test func objectsDecodeWithCursorAndPrefix() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("r2-objects")) }
        let page = try await client(stub).r2Objects(accountID: "acc1", bucket: "media", prefix: "img/", cursor: "C0")
        #expect(page.objects.map(\.key) == ["img/a.png", "img/b file.png"])
        #expect(page.objects[0].size == 2048)
        #expect(page.nextCursor == "RC1")
        let q = stub.recorded.first?.request.url?.query ?? ""
        #expect(q.contains("prefix=img/") && q.contains("cursor=C0"))
    }

    @Test func createValidatesNameThenPosts() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"name\":\"new-bucket\"}}".utf8)) }
        let b = try await client(stub).createR2Bucket(accountID: "acc1", name: "new-bucket")
        #expect(b.name == "new-bucket")
        let c = client(stub)
        await #expect(throws: WorkerValidationError.invalidName) { _ = try await c.createR2Bucket(accountID: "acc1", name: "Bad_Name") }
        #expect(stub.recorded.count == 1)
    }

    @Test func bucketNameRules() {
        #expect(validBucketName("media") && validBucketName("a-b-c") && validBucketName("abc"))
        #expect(!validBucketName("ab") && !validBucketName("-abc") && !validBucketName("abc-") && !validBucketName("ABC") && !validBucketName(String(repeating: "a", count: 64)))
    }

    @Test func deleteObjectEncodesTheKeyAndDeleteBucketUsesDelete() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteR2Object(accountID: "acc1", bucket: "media", key: "img/b file.png")
        try await client(stub).deleteR2Bucket(accountID: "acc1", bucket: "media")
        #expect(stub.recorded[0].request.url?.absoluteString.hasSuffix("/objects/img%2Fb%20file.png") == true)
        #expect(stub.recorded.map { $0.request.httpMethod } == ["DELETE", "DELETE"])
    }
}
