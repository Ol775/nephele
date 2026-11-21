import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct R2StoreTests {
    func make(denyWrites: Bool = false) async throws -> (R2Store, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            let q = req.url?.query ?? ""
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if req.httpMethod == "POST" && p.hasSuffix("/r2/buckets") { return TestAPI.reply(req, TestAPI.ok("{\"name\":\"fresh-one\"}")) }
            if p.hasSuffix("/objects") {
                if q.contains("cursor=O1") { return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":[{\"key\":\"b\"},{\"key\":\"c\"}],\"result_info\":{\"cursor\":\"\"}}") }
                return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":[{\"key\":\"a\"},{\"key\":\"b\"}],\"result_info\":{\"cursor\":\"O1\"}}")
            }
            if p.hasSuffix("/r2/buckets") { return TestAPI.reply(req, TestAPI.ok("{\"buckets\":[{\"name\":\"media\"},{\"name\":\"backups\"}]}")) }
            return TestAPI.base(req)
        }
        let store = R2Store(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsBucketsSortedAndObjectsPageWithoutDuplicates() async throws {
        let (store, _) = try await make()
        #expect(store.buckets.value?.map(\.name) == ["backups", "media"])
        await store.select(store.buckets.value?.first)
        #expect(store.objects.map(\.key) == ["a", "b"])
        await store.loadMore()
        #expect(store.objects.map(\.key) == ["a", "b", "c"])
        #expect(store.nextCursor == nil)
    }

    @Test func deleteObjectNeedsConfirmationAndSendsOnce() async throws {
        let (store, stub) = try await make()
        await store.select(store.buckets.value?.first)
        store.requestDelete(try #require(store.objects.first))
        #expect(writes(stub).isEmpty)
        let pending = try #require(store.confirm.pending)
        #expect(pending.message(bucket: "backups").contains("backups"))
        await store.confirmChange(pending)
        await store.confirmChange(pending)
        #expect(writes(stub).count == 1)
        #expect(store.objects.map(\.key) == ["b"])
    }

    @Test func createRejectsBadNamesAndDeleteNeedsTheTypedName() async throws {
        let (store, stub) = try await make()
        await store.create("Bad_Name")
        #expect(store.formError != nil && writes(stub).isEmpty)
        await store.create("fresh-one")
        #expect(store.buckets.value?.map(\.name).contains("fresh-one") == true)
        let b = try #require(store.buckets.value?.first { $0.name == "media" })
        await store.delete(b, typedName: "medi")
        #expect(store.formError != nil)
        await store.delete(b, typedName: "media")
        #expect(store.buckets.value?.map(\.name).contains("media") == false)
    }

    @Test func forbiddenWriteDisablesWritesAndKeepsReads() async throws {
        let (store, _) = try await make(denyWrites: true)
        await store.select(store.buckets.value?.first)
        store.requestDelete(try #require(store.objects.first))
        await store.confirmChange(try #require(store.confirm.pending))
        #expect(store.canWrite == false)
        #expect(store.formError?.contains("Workers R2 Storage Edit") == true)
        #expect(store.objects.count == 2)
    }
}
