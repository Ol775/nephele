import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerTriggersTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    func bodyJSON(_ rec: StubServer.Recorded) throws -> JSONValue {
        let raw = try #require(rec.body)
        return try JSONDecoder().decode(JSONValue.self, from: raw)
    }

    @Test func routesDecodeAndScriptIsOptional() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-routes")) }
        let routes = try await client(stub).workerRoutes(zoneID: "z1")
        #expect(routes.map(\.id) == ["r1", "r2", "r3"])
        #expect(routes[2].script == nil)
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/zones/z1/workers/routes")
    }

    @Test func routesCreateBodyHasPatternAndScript() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"r9\"}}".utf8)) }
        try await client(stub).createWorkerRoute(zoneID: "z1", pattern: "api.example.dev/*", script: "hello-api")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "POST")
        let json = try bodyJSON(rec)
        #expect(json["pattern"] == .string("api.example.dev/*"))
        #expect(json["script"] == .string("hello-api"))
    }

    @Test func deleteRouteUsesDeleteOnRoutePath() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"r1\"}}".utf8)) }
        try await client(stub).deleteWorkerRoute(zoneID: "z1", id: "r1")
        #expect(stub.recorded.first?.request.httpMethod == "DELETE")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/zones/z1/workers/routes/r1")
    }

    @Test func domainsAreRequestedForThisWorkerOnly() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-domains")) }
        let all = try await client(stub).workerDomains(accountID: "acc1", service: "hello-api")
        #expect(stub.recorded.first?.request.url?.query?.contains("service=hello-api") == true)
        #expect(all.first?.hostname == "api.example.dev")
        #expect(all.first?.zoneName == "example.dev")
    }

    @Test func attachDomainPutsHostnameServiceAndZone() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"d\"}}".utf8)) }
        try await client(stub).attachWorkerDomain(accountID: "acc1", hostname: "api.example.dev", script: "hello-api", zoneID: "z1")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "PUT")
        let json = try bodyJSON(rec)
        #expect(json["hostname"] == .string("api.example.dev"))
        #expect(json["service"] == .string("hello-api"))
        #expect(json["zone_id"] == .string("z1"))
    }

    @Test func schedulesDecodeAndPutBodyShape() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-schedules")) }
        #expect(try await client(stub).workerSchedules(accountID: "acc1", script: "hello-api") == ["*/30 * * * *", "0 6 * * MON"])
        try await client(stub).setWorkerSchedules(accountID: "acc1", script: "hello-api", ["0 6 * * MON"])
        let rec = try #require(stub.recorded.last)
        #expect(rec.request.httpMethod == "PUT")
        #expect(try bodyJSON(rec) == .array([.object(["cron": .string("0 6 * * MON")])]))
    }

    @Test func validRoutePatternAcceptsSubdomainAndWildcardRejectsOtherZone() {
        #expect(validRoutePattern("example.dev/*", zone: "example.dev"))
        #expect(validRoutePattern("api.example.dev/v1/*", zone: "example.dev"))
        #expect(validRoutePattern("*.example.dev/*", zone: "example.dev"))
        #expect(!validRoutePattern("other.dev/*", zone: "example.dev"))
        #expect(!validRoutePattern("notexample.dev/*", zone: "example.dev"))
        #expect(!validRoutePattern("", zone: "example.dev"))
        #expect(!validRoutePattern("api.example.dev/ *", zone: "example.dev"))
    }

    @Test func validCronRejectsFourFieldsAndLetters() {
        #expect(validCron("*/30 * * * *") && validCron("0 6 * * MON") && validCron("0 0 1 JAN *") && validCron("5,10 1-3 * * *"))
        #expect(!validCron("* * * *") && !validCron("* * * * * *") && !validCron("a b c d e") && !validCron(""))
    }
}
