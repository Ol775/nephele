import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct UsageStoreTests {
    nonisolated static let hourlyJSON = "{\"data\":{\"viewer\":{\"zones\":[{\"httpRequests1hGroups\":[{\"dimensions\":{\"datetime\":\"2026-11-21T10:00:00Z\"},\"sum\":{\"requests\":50,\"cachedRequests\":25,\"threats\":1}}]}]}},\"errors\":null}"
    nonisolated static let dailyJSON = "{\"data\":{\"viewer\":{\"zones\":[{\"httpRequests1dGroups\":[{\"dimensions\":{\"date\":\"2026-11-20\"},\"sum\":{\"requests\":200,\"cachedRequests\":100,\"threats\":3}}]}]}},\"errors\":null}"
    nonisolated static let denied = "{\"data\":null,\"errors\":[{\"message\":\"not authorized to access this resource\"}]}"
    nonisolated static let meterOK = "{\"data\":{\"viewer\":{\"accounts\":[{\"workersInvocationsAdaptive\":[{\"sum\":{\"requests\":10}}],\"kvOperationsAdaptiveGroups\":[],\"d1AnalyticsAdaptiveGroups\":[],\"r2StorageAdaptiveGroups\":[]}]}},\"errors\":null}"

    func server(zonesEmpty: Bool = false, metersDenied: Bool = false) -> StubServer {
        StubServer { req in
            let path = req.url!.path
            if path.hasSuffix("/zones") && req.url?.query?.contains("per_page=50") == true && zonesEmpty { return TestAPI.reply(req, TestAPI.ok("[]")) }
            guard path.hasSuffix("/graphql") else { return TestAPI.base(req) }
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            if body.contains("httpRequests1hGroups") { return TestAPI.reply(req, Self.hourlyJSON) }
            if body.contains("httpRequests1dGroups") { return TestAPI.reply(req, Self.dailyJSON) }
            return TestAPI.reply(req, metersDenied ? Self.denied : Self.meterOK)
        }
    }
    func graphQLCount(_ stub: StubServer, containing text: String) -> Int {
        stub.recorded.filter { $0.request.url!.path.hasSuffix("/graphql") && (String(data: $0.body ?? Data(), encoding: .utf8) ?? "").contains(text) }.count
    }
    func make(_ stub: StubServer) async throws -> UsageStore {
        let session = try await TestAPI.readySession(stub)
        return UsageStore(session: session, domains: DomainsStore(session: session))
    }

    @Test func loadFillsTrafficAndMeters() async throws {
        let store = try await make(server())
        await store.load()
        #expect(store.traffic.value?.totalRequests == 50)
        #expect(store.meters.value?.isEmpty == false)
    }

    @Test func changingRangeRefetchesTrafficOnly() async throws {
        let stub = server()
        let store = try await make(stub)
        await store.load()
        let trafficBefore = graphQLCount(stub, containing: "httpRequests1")
        let metersBefore = graphQLCount(stub, containing: "workersInvocationsAdaptive")
        await store.setRange(.d30)
        #expect(store.range == .d30)
        #expect(graphQLCount(stub, containing: "httpRequests1") == trafficBefore + 1)
        #expect(graphQLCount(stub, containing: "workersInvocationsAdaptive") == metersBefore)
    }

    @Test func meterDatasetsDeniedShowsPermissionStateWhileTrafficStillLoads() async throws {
        let store = try await make(server(metersDenied: true))
        await store.load()
        #expect(store.traffic.value != nil)
        #expect(store.meters.failure == .permissionDenied("not authorized to access this resource"))
    }

    @Test func noZonesGivesEmptyTrafficNotError() async throws {
        let stub = server(zonesEmpty: true)
        let store = try await make(stub)
        await store.load()
        #expect(store.traffic.value?.points.isEmpty == true)
        #expect(graphQLCount(stub, containing: "httpRequests1") == 0)
    }

    @Test func clearCacheReloadsEverything() async throws {
        let stub = server()
        let store = try await make(stub)
        await store.load()
        let before = graphQLCount(stub, containing: "httpRequests1")
        await store.load(force: true)
        #expect(graphQLCount(stub, containing: "httpRequests1") == before + 1)
    }
}
