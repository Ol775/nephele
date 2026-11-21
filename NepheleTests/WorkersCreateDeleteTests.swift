import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkersCreateDeleteTests {
    nonisolated static let list = "[{\"id\":\"hello-api\"},{\"id\":\"cron-job\"}]"

    func make(denyWrites: Bool = false) async throws -> (WorkersStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod == "POST" && p.hasSuffix("/workers/workers") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"w\",\"name\":\"fresh\"}")) }
            if req.httpMethod == "POST" && p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"v1\",\"number\":1}")) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if p.hasSuffix("/workers/scripts") { return TestAPI.reply(req, TestAPI.ok(Self.list)) }
            return TestAPI.base(req)
        }
        let store = WorkersStore(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func createRejectsInvalidAndDuplicateNamesBeforeRequest() async throws {
        let (store, stub) = try await make()
        #expect(await store.create(name: "Bad Name", template: .hello) == nil)
        #expect(store.formError != nil)
        store.formError = nil
        #expect(await store.create(name: "hello-api", template: .hello) == nil)
        #expect(store.formError?.contains("already") == true)
        #expect(writes(stub).isEmpty)
    }

    @Test func createUploadsVersionNotDeployment() async throws {
        let (store, stub) = try await make()
        let created = await store.create(name: "fresh", template: .scheduledJob)
        #expect(created?.id == "fresh")
        #expect(writes(stub).count == 2)
        #expect(!writes(stub).contains { $0.request.url!.path.hasSuffix("/deployments") })
        #expect(store.workers.value?.contains { $0.id == "fresh" } == true)
    }

    @Test func deleteRequiresTypingExactName() async throws {
        let (store, stub) = try await make()
        let target = try #require(store.workers.value?.first { $0.id == "hello-api" })
        await store.delete(target, typedName: "hello")
        #expect(store.formError != nil)
        #expect(writes(stub).isEmpty)
        #expect(store.workers.value?.count == 2)
    }

    @Test func deleteRemovesFromListAfterSuccess() async throws {
        let (store, stub) = try await make()
        let target = try #require(store.workers.value?.first { $0.id == "hello-api" })
        await store.delete(target, typedName: "hello-api")
        #expect(writes(stub).filter { $0.request.httpMethod == "DELETE" }.count == 1)
        #expect(store.workers.value?.map(\.id) == ["cron-job"])
        #expect(store.formError == nil)
    }

    @Test func deleteForbiddenKeepsWorkerAndShowsHint() async throws {
        let (store, _) = try await make(denyWrites: true)
        let target = try #require(store.workers.value?.first { $0.id == "hello-api" })
        await store.delete(target, typedName: "hello-api")
        #expect(store.workers.value?.count == 2)
        #expect(store.formError?.contains("Workers Scripts Edit") == true)
    }
}
