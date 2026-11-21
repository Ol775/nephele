import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkersStoreTests {
    nonisolated static let list = "[{\"id\":\"hello-api\",\"modified_on\":\"2026-11-18T09:30:00Z\",\"handlers\":[\"fetch\"]},{\"id\":\"cron-job\",\"handlers\":[\"scheduled\"]}]"
    nonisolated static let deployments = "{\"deployments\":[{\"id\":\"d1\",\"created_on\":\"2026-11-18T09:31:00Z\",\"versions\":[{\"version_id\":\"v-0002-aaaa\",\"percentage\":100}]}]}"

    func session(deny: [String] = []) async throws -> Session {
        let stub = StubServer { req in
            let p = req.url!.path
            if deny.contains(where: { p.contains($0) }) { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if p.hasSuffix("/workers/scripts") { return TestAPI.reply(req, TestAPI.ok(Self.list)) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok(Self.deployments)) }
            return TestAPI.base(req)
        }
        return try await TestAPI.readySession(stub)
    }

    @Test func loadsIntoLoadedState() async throws {
        let store = WorkersStore(session: try await session())
        await store.load()
        #expect(store.workers.value?.map(\.id) == ["cron-job", "hello-api"])
    }

    @Test func permissionDeniedBecomesFailed() async throws {
        let store = WorkersStore(session: try await session(deny: ["/workers/scripts"]))
        await store.load()
        #expect(store.workers.failure == .permissionDenied("Authentication error"))
    }

    @Test func resetClearsData() async throws {
        let store = WorkersStore(session: try await session())
        await store.load()
        store.reset()
        #expect(store.workers.value == nil)
    }

    @Test func forbiddenDeploymentsDoNotBlockTheOverview() async throws {
        let s = try await session(deny: ["/deployments"])
        let script = WorkerScript(id: "hello-api")
        let store = WorkerStore(script: script, session: s)
        await store.load()
        #expect(store.latestDeployment.failure != nil)
        #expect(store.script.id == "hello-api")
    }

    @Test func overviewShowsNewestDeployment() async throws {
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: try await session())
        await store.load()
        #expect(store.latestDeployment.value??.versions.first?.versionId == "v-0002-aaaa")
    }

    @Test func noteWriteDeniedDisablesWrites() async throws {
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: try await session())
        #expect(store.canWrite)
        store.noteWriteDenied()
        #expect(store.canWrite == false)
    }
}
