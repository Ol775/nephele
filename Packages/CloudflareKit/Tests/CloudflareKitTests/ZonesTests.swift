import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct ZonesTests {
    @Test func zonesMergesAllPages() async throws {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!), fixture(page(of: req) == 1 ? "zones-page1" : "zones-page2"))
        }
        let zones = try await CFClient(token: "t", session: stub.session).zones()
        #expect(zones.count == 53)
        #expect(stub.recorded.map { page(of: $0.request) } == [1, 2])
    }

    @Test func zonesEmptyAccountReturnsEmptyArray() async throws {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":[],\"result_info\":{\"page\":1,\"per_page\":50,\"total_pages\":0,\"total_count\":0}}".utf8))
        }
        let zones = try await CFClient(token: "t", session: stub.session).zones()
        #expect(zones.isEmpty)
    }

    @Test func zoneDecodesPlanAndAccount() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("zones-page2")) }
        let zone = try #require(try await CFClient(token: "t", session: stub.session).zones().first)
        #expect(zone.name == "example-51.dev")
        #expect(zone.planName == "Free Website")
        #expect(zone.accountID == "acc0001")
        #expect(zone.nameServers.count == 2)
        #expect(zone.paused == false)
    }
}
