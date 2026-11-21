import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct AlertsTests {
    func event(_ id: String) -> AlertEvent {
        AlertEvent(id: id, name: "Event \(id)", alertType: "incident_alert", sent: Date(timeIntervalSince1970: 1_700_000_000), severity: .info)
    }

    @Test func historyMapsKnownAlertTypesToSeverity() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("alert-history")) }
        let events = try await CFClient(token: "t", session: stub.session).alertHistory(accountID: "acc1")
        #expect(events.map(\.id) == ["evt1", "evt2", "evt3"])
        #expect(events.map(\.severity) == [.warning, .critical, .info])
        #expect(abs(events[0].sent.timeIntervalSince(ISO8601DateFormatter().date(from: "2026-11-20T10:00:00Z")!) - 0.123) < 0.001)
        #expect(stub.recorded[0].request.url?.path == "/client/v4/accounts/acc1/alerting/v3/history")
    }

    @Test func policiesDecodeEnabledFlag() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("alert-policies")) }
        let policies = try await CFClient(token: "t", session: stub.session).alertPolicies(accountID: "acc1")
        #expect(policies.map(\.enabled) == [true, false])
        #expect(stub.recorded[0].request.url?.path == "/client/v4/accounts/acc1/alerting/v3/policies")
    }

    @Test func emptyHistoryIsEmpty() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":[]}".utf8)) }
        #expect(try await CFClient(token: "t", session: stub.session).alertHistory(accountID: "acc1").isEmpty)
    }

    @Test func dedupeReturnsEachEventOnce() {
        var d = AlertDeduper()
        let batch = [event("a"), event("b")]
        #expect(d.newEvents(batch).map(\.id) == ["a", "b"])
        #expect(d.newEvents(batch).isEmpty)
        #expect(d.newEvents(batch + [event("c")]).map(\.id) == ["c"])
    }

    @Test func dedupeKeepsOnlyMaxRemembered() {
        var d = AlertDeduper(maxRemembered: 500)
        let batch = (0...500).map { event("e\($0)") }
        #expect(d.newEvents(batch).count == 501)
        #expect(d.newEvents(batch).map(\.id) == ["e0"])
    }

    @Test func primingMarksExistingEventsSeenWithoutReturningThem() {
        var d = AlertDeduper()
        #expect(d.isPrimed == false)
        d.prime([event("a")])
        #expect(d.isPrimed)
        #expect(d.newEvents([event("a"), event("b")]).map(\.id) == ["b"])
    }

    @Test func dedupeStateRoundTripsThroughJSON() throws {
        var d = AlertDeduper()
        _ = d.newEvents([event("a")])
        var restored = try JSONDecoder().decode(AlertDeduper.self, from: JSONEncoder().encode(d))
        #expect(restored.newEvents([event("a")]).isEmpty)
    }
}
