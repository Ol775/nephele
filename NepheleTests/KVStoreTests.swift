import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct KVStoreTests {
    nonisolated static let namespaces = "[{\"id\":\"ns2\",\"title\":\"SESSIONS\"},{\"id\":\"ns1\",\"title\":\"cache\"}]"

    func make(denyWrites: Bool = false, binary: Bool = false) async throws -> (KVStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            let q = req.url?.query ?? ""
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "PUT" || req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if req.httpMethod == "POST" && p.hasSuffix("/kv/namespaces") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"ns3\",\"title\":\"new\"}")) }
            if p.hasSuffix("/keys") {
                if q.contains("prefix=zz") { return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"zz:1\"}],\"result_info\":{\"count\":1,\"cursor\":\"\"}}") }
                if q.contains("cursor=C1") { return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"b\"},{\"name\":\"c\"}],\"result_info\":{\"count\":2,\"cursor\":\"\"}}") }
                return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"a\"},{\"name\":\"b\"}],\"result_info\":{\"count\":2,\"cursor\":\"C1\"}}")
            }
            if p.contains("/values/") { return (StubURLProtocol.response(req.url!), binary ? Data([0xFF, 0x00, 0xFE]) : Data("hello".utf8)) }
            if p.hasSuffix("/kv/namespaces") { return TestAPI.reply(req, TestAPI.ok(Self.namespaces)) }
            return TestAPI.base(req)
        }
        let store = KVStore(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsNamespacesSortedByTitle() async throws {
        let (store, _) = try await make()
        #expect(store.namespaces.value?.map(\.title) == ["cache", "SESSIONS"])
    }

    @Test func selectingLoadsKeysAndLoadMoreAppendsWithoutDuplicates() async throws {
        let (store, _) = try await make()
        await store.select(store.namespaces.value?.first)
        #expect(store.keys.map(\.name) == ["a", "b"])
        #expect(store.nextCursor == "C1")
        await store.loadMore()
        #expect(store.keys.map(\.name) == ["a", "b", "c"])
        #expect(store.nextCursor == nil)
    }

    @Test func changingThePrefixResetsTheList() async throws {
        let (store, _) = try await make()
        await store.select(store.namespaces.value?.first)
        store.prefix = "zz"
        await store.loadKeys(reset: true)
        #expect(store.keys.map(\.name) == ["zz:1"])
    }

    @Test func textValueFillsTheDraftAndSaveSendsTheBytes() async throws {
        let (store, stub) = try await make()
        await store.select(store.namespaces.value?.first)
        await store.open(try #require(store.keys.first))
        #expect(store.draft == "hello")
        #expect(store.hasUnsavedChanges == false)
        store.draft = "hello world"
        #expect(store.hasUnsavedChanges)
        await store.saveValue()
        #expect(writes(stub).first?.body == Data("hello world".utf8))
        #expect(store.hasUnsavedChanges == false)
    }

    @Test func binaryValueIsNeverWrittenBack() async throws {
        let (store, stub) = try await make(binary: true)
        await store.select(store.namespaces.value?.first)
        await store.open(try #require(store.keys.first))
        #expect(store.value.value?.isText == false)
        await store.saveValue()
        #expect(writes(stub).isEmpty)
    }

    @Test func deleteKeyNeedsConfirmationAndSendsOnce() async throws {
        let (store, stub) = try await make()
        await store.select(store.namespaces.value?.first)
        store.requestDelete(try #require(store.keys.first))
        #expect(writes(stub).isEmpty)
        let pending = try #require(store.confirm.pending)
        #expect(pending.message(namespace: "cache").contains("cache"))
        await store.confirmChange(pending)
        await store.confirmChange(pending)
        #expect(writes(stub).count == 1)
        #expect(store.keys.map(\.name) == ["b"])
    }

    @Test func deleteNamespaceRequiresTheTypedTitle() async throws {
        let (store, stub) = try await make()
        let ns = try #require(store.namespaces.value?.first)
        await store.deleteNamespace(ns, typedName: "nope")
        #expect(store.formError != nil && writes(stub).isEmpty)
        await store.deleteNamespace(ns, typedName: "cache")
        #expect(store.namespaces.value?.map(\.title) == ["SESSIONS"])
    }

    @Test func createNamespaceAddsItAndRejectsEmptyTitles() async throws {
        let (store, _) = try await make()
        await store.createNamespace("  ")
        #expect(store.formError != nil)
        await store.createNamespace("new")
        #expect(store.namespaces.value?.map(\.title).contains("new") == true)
    }

    @Test func forbiddenWriteDisablesWritesAndKeepsReads() async throws {
        let (store, _) = try await make(denyWrites: true)
        await store.select(store.namespaces.value?.first)
        await store.addKey("k", value: "v")
        #expect(store.canWrite == false)
        #expect(store.formError?.contains("Workers KV Storage Edit") == true)
        #expect(store.keys.map(\.name) == ["a", "b"])
    }

    @Test func dotKeyNamesAreRefusedBeforeAnyRequest() async throws {
        let (store, stub) = try await make()
        await store.select(store.namespaces.value?.first)
        await store.addKey("..", value: "v")
        #expect(store.formError != nil)
        await store.addKey(".", value: "v")
        #expect(writes(stub).isEmpty)
    }
}
