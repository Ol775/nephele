import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct AnalyticsTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-21T15:30:00Z")!

    func bodyText(_ r: StubServer.Recorded) -> String { String(data: r.body ?? Data(), encoding: .utf8) ?? "" }

    func meterServer(overrides: [String: Data] = [:]) -> StubServer {
        StubServer { req in
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            let json: String
            if let key = overrides.keys.first(where: { body.contains($0) }) { return (StubURLProtocol.response(req.url!), overrides[key]!) }
            if body.contains("workersInvocationsAdaptive") { json = "{\"data\":{\"viewer\":{\"accounts\":[{\"workersInvocationsAdaptive\":[{\"sum\":{\"requests\":40000}},{\"sum\":{\"requests\":22000}}]}]}},\"errors\":null}" }
            else if body.contains("kvOperationsAdaptiveGroups") { json = "{\"data\":{\"viewer\":{\"accounts\":[{\"kvOperationsAdaptiveGroups\":[{\"sum\":{\"requests\":91000},\"dimensions\":{\"actionType\":\"read\"}},{\"sum\":{\"requests\":120},\"dimensions\":{\"actionType\":\"write\"}},{\"sum\":{\"requests\":5},\"dimensions\":{\"actionType\":\"list\"}}]}]}},\"errors\":null}" }
            else if body.contains("d1AnalyticsAdaptiveGroups") { json = "{\"data\":{\"viewer\":{\"accounts\":[{\"d1AnalyticsAdaptiveGroups\":[{\"sum\":{\"rowsRead\":1200000,\"rowsWritten\":3000}}]}]}},\"errors\":null}" }
            else { json = "{\"data\":{\"viewer\":{\"accounts\":[{\"r2StorageAdaptiveGroups\":[{\"max\":{\"payloadSize\":1500000000,\"metadataSize\":300000000},\"dimensions\":{\"bucketName\":\"media\",\"datetime\":\"2026-11-21T14:00:00Z\"}},{\"max\":{\"payloadSize\":1000000000,\"metadataSize\":0},\"dimensions\":{\"bucketName\":\"media\",\"datetime\":\"2026-11-21T10:00:00Z\"}}]}]}},\"errors\":null}" }
            return (StubURLProtocol.response(req.url!), Data(json.utf8))
        }
    }

    @Test func fractionClampsToOneAndIsHotAboveEightyFivePercent() {
        let hot = Meter(label: "KV reads", used: 91_000, limit: 100_000, unit: "")
        #expect(hot.isHot)
        #expect(Meter(label: "x", used: 120_000, limit: 100_000, unit: "").fraction == 1.0)
        #expect(Meter(label: "x", used: 10, limit: 100, unit: "").isHot == false)
        #expect(Meter(label: "x", used: 1, limit: 0, unit: "").fraction == 0)
    }

    @Test func cacheHitRatioHandlesZeroRequests() {
        let empty = TrafficSummary(points: [])
        #expect(empty.cacheHitRatio == 0)
        #expect(empty.totalRequests == 0)
    }

    @Test func h24UsesHourlyDatasetAndOthersDaily() {
        #expect(AnalyticsQueries.traffic(range: .h24).contains("httpRequests1hGroups"))
        #expect(AnalyticsQueries.traffic(range: .d7).contains("httpRequests1dGroups"))
        #expect(AnalyticsQueries.traffic(range: .d30).contains("httpRequests1dGroups"))
    }

    @Test func trafficDecodesFixtureAndSumsTotals() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("graphql-traffic-1d")) }
        let summary = try await CFClient(token: "t", session: stub.session).traffic(zoneIDs: ["zoneA", "zoneB"], range: .d7, now: now)
        #expect(summary.points.count == 2)
        #expect(summary.points.map(\.requests) == [150, 225])
        #expect(summary.totalRequests == 375)
        #expect(abs(summary.cacheHitRatio - 175.0 / 375.0) < 0.0001)
        #expect(summary.threats == 6)
        let sent = bodyText(try #require(stub.recorded.first))
        #expect(sent.contains("zoneA") && sent.contains("zoneB") && sent.contains("httpRequests1dGroups"))
    }

    @Test func trafficWithNoZonesReturnsEmptySummaryWithoutNetwork() async throws {
        let stub = StubServer()
        let summary = try await CFClient(token: "t", session: stub.session).traffic(zoneIDs: [], range: .h24, now: now)
        #expect(summary.points.isEmpty)
        #expect(stub.recorded.isEmpty)
    }

    @Test func trafficPermissionDeniedPropagates() async {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"data\":null,\"errors\":[{\"message\":\"zone does not have access to the path\"}]}".utf8)) }
        let c = CFClient(token: "t", session: stub.session)
        await #expect(throws: CloudflareError.permissionDenied("zone does not have access to the path")) {
            _ = try await c.traffic(zoneIDs: ["z"], range: .d7, now: now)
        }
    }

    @Test func accountMetersBuildsOneMeterPerAllowance() async throws {
        let stub = meterServer()
        let meters = try await CFClient(token: "t", session: stub.session).accountMeters(accountID: "acc1", now: now)
        #expect(meters.map(\.label) == ["Workers requests", "KV reads", "KV writes", "D1 rows read", "D1 rows written", "R2 storage"])
        #expect(meters.map(\.used) == [62_000, 91_000, 120, 1_200_000, 3_000, 1.8])
        #expect(meters[0].limit == PlanAllowances.free["workersRequestsPerDay"])
        #expect(meters[5].unit == "GB")
    }

    @Test func accountMetersPartialAccessKeepsTheMetersThatLoad() async throws {
        let denied = Data("{\"data\":null,\"errors\":[{\"message\":\"not authorized to access this resource\"}]}".utf8)
        let stub = meterServer(overrides: ["workersInvocationsAdaptive": denied])
        let meters = try await CFClient(token: "t", session: stub.session).accountMeters(accountID: "acc1", now: now)
        #expect(meters.count == 5)
        #expect(!meters.contains { $0.label == "Workers requests" })
    }

    @Test func accountMetersAllDeniedThrowsPermissionDenied() async {
        let denied = Data("{\"data\":null,\"errors\":[{\"message\":\"not authorized to access this resource\"}]}".utf8)
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), denied) }
        let c = CFClient(token: "t", session: stub.session)
        await #expect(throws: CloudflareError.permissionDenied("not authorized to access this resource")) {
            _ = try await c.accountMeters(accountID: "acc1", now: now)
        }
    }
}
