import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct WorkerTriggersStoreTests {
    nonisolated static let z1 = Zone(id: "z1", name: "example.dev", status: "active", planName: "Free", accountID: "acc1")
    nonisolated static let z2 = Zone(id: "z2", name: "other.dev", status: "active", planName: "Free", accountID: "acc1")

    func make(denyZone2: Bool = true) async throws -> (WorkerStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if p == "/client/v4/zones/z2/workers/routes" && denyZone2 { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if p == "/client/v4/zones/z1/workers/routes" && req.httpMethod == "GET" {
                return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"r1\",\"pattern\":\"api.example.dev/*\",\"script\":\"hello-api\"},{\"id\":\"r2\",\"pattern\":\"example.dev/x/*\",\"script\":\"other\"}]"))
            }
            if p == "/client/v4/zones/z2/workers/routes" && req.httpMethod == "GET" { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"r3\",\"pattern\":\"other.dev/*\",\"script\":\"hello-api\"}]")) }
            if p.hasSuffix("/workers/domains") && req.httpMethod == "GET" {
                return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"dom1\",\"hostname\":\"api.example.dev\",\"service\":\"hello-api\",\"zone_id\":\"z1\",\"zone_name\":\"example.dev\"}]"))
            }
            if p.hasSuffix("/schedules") && req.httpMethod == "GET" { return TestAPI.reply(req, TestAPI.ok("{\"schedules\":[{\"cron\":\"*/30 * * * *\"}]}")) }
            if req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.ok("{}")) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: session)
        await store.loadTriggers(zones: [Self.z1, Self.z2])
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsOnlyThisWorkersRoutesDomainsAndCrons() async throws {
        let (store, _) = try await make(denyZone2: false)
        let t = try #require(store.triggers.value)
        #expect(t.routes.map(\.route.id) == ["r1", "r3"])
        #expect(t.domains.map(\.hostname) == ["api.example.dev"])
        #expect(t.crons == ["*/30 * * * *"])
        #expect(t.unreadableZones.isEmpty)
    }

    @Test func oneForbiddenZoneDoesNotHideOtherRoutes() async throws {
        let (store, _) = try await make()
        let t = try #require(store.triggers.value)
        #expect(t.routes.map(\.route.id) == ["r1"])
        #expect(t.unreadableZones == ["other.dev"])
    }

    @Test func invalidCronShowsErrorAndSendsNothing() async throws {
        let (store, stub) = try await make()
        await store.addCron("* * * *")
        #expect(store.formError != nil)
        #expect(writes(stub).isEmpty)
    }

    @Test func validCronIsAddedToTheExistingList() async throws {
        let (store, stub) = try await make()
        await store.addCron("0 6 * * MON")
        let rec = try #require(writes(stub).first)
        let raw = try #require(rec.body)
        let json = try JSONDecoder().decode(JSONValue.self, from: raw)
        #expect(json == .array([.object(["cron": .string("*/30 * * * *")]), .object(["cron": .string("0 6 * * MON")])]))
        #expect(store.triggers.value?.crons == ["*/30 * * * *", "0 6 * * MON"])
    }

    @Test func invalidRoutePatternSendsNothing() async throws {
        let (store, stub) = try await make()
        await store.addRoute(pattern: "other.dev/*", zone: Self.z1)
        #expect(store.formError != nil)
        #expect(writes(stub).isEmpty)
    }

    @Test func removingACronOrRouteNeedsConfirmation() async throws {
        let (store, stub) = try await make()
        store.requestChange(.removeCron("*/30 * * * *"))
        #expect(writes(stub).isEmpty)
        await store.confirmChange(.removeCron("*/30 * * * *"))
        #expect(writes(stub).count == 1)
        store.requestChange(.removeRoute(id: "r1", pattern: "api.example.dev/*", zoneID: "z1"))
        let pending = try #require(store.confirm.pending)
        #expect(pending.message(worker: "hello-api").contains("api.example.dev/*"))
        await store.confirmChange(pending)
        #expect(writes(stub).filter { $0.request.httpMethod == "DELETE" }.count == 1)
        #expect(store.triggers.value?.routes.map(\.route.id) == [])
    }

    @Test func forbiddenWriteDisablesControls() async throws {
        let stub = StubServer { req in
            if req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.url!.path.hasSuffix("/schedules") { return TestAPI.reply(req, TestAPI.ok("{\"schedules\":[]}")) }
            return TestAPI.base(req)
        }
        let denied = WorkerStore(script: WorkerScript(id: "hello-api"), session: try await TestAPI.readySession(stub))
        await denied.loadTriggers(zones: [])
        await denied.addCron("0 6 * * *")
        #expect(denied.canWrite == false)
        #expect(denied.formError?.contains("Workers Scripts Edit") == true)
    }
}
