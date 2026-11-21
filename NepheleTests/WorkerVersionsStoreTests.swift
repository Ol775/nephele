import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkerVersionsStoreTests {
    nonisolated static let versions = "{\"items\":[{\"id\":\"v-0001-bbbb\",\"number\":1,\"metadata\":{\"created_on\":\"2026-11-01T09:30:00Z\"}},{\"id\":\"v-0002-aaaa\",\"number\":2,\"metadata\":{\"created_on\":\"2026-11-18T09:30:00Z\"}}]}"
    nonisolated static func deployments(live: String) -> String {
        "{\"deployments\":[{\"id\":\"d\(live)\",\"created_on\":\"2026-11-18T09:31:00Z\",\"versions\":[{\"version_id\":\"\(live)\",\"percentage\":100}]}]}"
    }
    nonisolated static let created = "{\"id\":\"d3\",\"created_on\":\"2026-11-19T10:00:00Z\",\"versions\":[{\"version_id\":\"v-0001-bbbb\",\"percentage\":100}]}"

    final class Live: @unchecked Sendable {
        private let lock = NSLock(); private var _id = "v-0002-aaaa"
        var id: String { get { lock.withLock { _id } } set { lock.withLock { _id = newValue } } }
    }

    func make(denyWrites: Bool = false) async throws -> (WorkerStore, StubServer) {
        let live = Live()
        let stub = StubServer { req in
            let p = req.url!.path
            if req.httpMethod == "POST" && p.hasSuffix("/deployments") {
                if denyWrites { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
                live.id = "v-0001-bbbb"
                return TestAPI.reply(req, TestAPI.ok(Self.created))
            }
            if p.hasSuffix("/versions") { return TestAPI.reply(req, TestAPI.ok(Self.versions)) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok(Self.deployments(live: live.id))) }
            return TestAPI.base(req)
        }
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: try await TestAPI.readySession(stub))
        await store.loadVersions()
        return (store, stub)
    }

    func posts(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod == "POST" } }

    @Test func loadsVersionsNewestFirstAndMarksTheLiveOne() async throws {
        let (store, _) = try await make()
        #expect(store.versions.value?.map(\.id) == ["v-0002-aaaa", "v-0001-bbbb"])
        #expect(store.liveVersionID == "v-0002-aaaa")
    }

    @Test func deployNeedsConfirmationAndSendsOnce() async throws {
        let (store, stub) = try await make()
        let old = try #require(store.versions.value?.last)
        store.requestDeploy(old)
        let pending = try #require(store.confirm.pending)
        #expect(posts(stub).isEmpty)
        await store.confirmChange(pending)
        await store.confirmChange(pending)
        #expect(posts(stub).count == 1)
    }

    @Test func rollbackWordingUsedForOlderVersion() async throws {
        let (store, _) = try await make()
        store.requestDeploy(try #require(store.versions.value?.last))
        let p = try #require(store.confirm.pending)
        #expect(p.title(worker: "hello-api").contains("Roll back"))
        #expect(p.message(worker: "hello-api").contains("hello-api"))
        #expect(p.message(worker: "hello-api").contains("v-0001-b"))
    }

    @Test func deployWordingUsedForNewerVersion() async throws {
        let (store, _) = try await make()
        let newer = try #require(store.versions.value?.first)
        // pretend the older one is live
        await store.confirmChange(.deploy(versionID: "v-0001-bbbb", label: "v-0001-b", rollback: true)) // not armed: ignored
        #expect(newer.id == "v-0002-aaaa")
        #expect(WorkerChange.deploy(versionID: newer.id, label: "x", rollback: false).title(worker: "hello-api").hasPrefix("Deploy"))
    }

    @Test func deployingTheLiveVersionIsDisabled() async throws {
        let (store, _) = try await make()
        let live = try #require(store.versions.value?.first)
        #expect(store.isLive(live))
        store.requestDeploy(live)
        #expect(store.confirm.pending == nil)
    }

    @Test func refreshAfterDeployUpdatesLiveMarker() async throws {
        let (store, _) = try await make()
        store.requestDeploy(try #require(store.versions.value?.last))
        await store.confirmChange(try #require(store.confirm.pending))
        #expect(store.liveVersionID == "v-0001-bbbb")
        #expect(store.latestDeployment.value??.versions.first?.versionId == "v-0001-bbbb")
    }

    @Test func forbiddenDeployDisablesWritesAndKeepsList() async throws {
        let (store, _) = try await make(denyWrites: true)
        store.requestDeploy(try #require(store.versions.value?.last))
        await store.confirmChange(try #require(store.confirm.pending))
        #expect(store.canWrite == false)
        #expect(store.versions.value?.count == 2)
        #expect(store.formError?.contains("Workers Scripts Edit") == true)
    }
}
