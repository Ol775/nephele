import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct DNSStoreTests {
    static let a = "{\"id\":\"r1\",\"type\":\"A\",\"name\":\"example.dev\",\"content\":\"192.0.2.10\",\"proxied\":true,\"ttl\":1}"
    static let mx = "{\"id\":\"r2\",\"type\":\"MX\",\"name\":\"example.dev\",\"content\":\"mail.example.dev\",\"proxied\":false,\"ttl\":1,\"priority\":10}"

    /// DNS endpoints: GET lists `records`, POST echoes a new record, PATCH echoes with proxied flipped, DELETE succeeds.
    func server(records: [String] = [a, mx], listStatus: Int = 200) -> StubServer {
        StubServer { req in
            let path = req.url!.path
            guard path.contains("/zones/z1/dns_records") else { return TestAPI.base(req) }
            switch req.httpMethod {
            case "GET": return listStatus == 200 ? TestAPI.reply(req, TestAPI.ok("[\(records.joined(separator: ","))]")) : TestAPI.reply(req, TestAPI.forbiddenBody, status: listStatus)
            case "POST": return TestAPI.reply(req, TestAPI.ok("{\"id\":\"new1\",\"type\":\"A\",\"name\":\"api.example.dev\",\"content\":\"192.0.2.55\",\"proxied\":true,\"ttl\":1}"))
            case "PATCH": return TestAPI.reply(req, TestAPI.ok("{\"id\":\"r1\",\"type\":\"A\",\"name\":\"example.dev\",\"content\":\"192.0.2.10\",\"proxied\":false,\"ttl\":1}"))
            default: return TestAPI.reply(req, TestAPI.ok("{\"id\":\"r1\"}"))
            }
        }
    }
    func count(_ stub: StubServer, _ method: String) -> Int { stub.recorded.filter { $0.request.httpMethod == method && $0.request.url!.path.contains("/dns_records") }.count }

    @Test func invalidDraftSetsFormErrorAndSendsNothing() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.add(DNSRecordDraft(type: "A", name: "api", content: "999.9.9.9", proxied: true))
        #expect(store.formError == "An A record needs an IPv4 address, such as 192.0.2.10.")
        #expect(count(stub, "POST") == 0)
    }

    @Test func addAppendsTheCreatedRecordAndClearsTheError() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        await store.add(DNSRecordDraft(type: "A", name: "api", content: "192.0.2.55", proxied: true))
        #expect(store.records.value?.map(\.id) == ["r1", "r2", "new1"])
        #expect(store.formError == nil)
        #expect(count(stub, "POST") == 1)
    }

    @Test func deleteDoesNothingUntilConfirmed() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let record = try #require(store.records.value?.first)
        store.requestDelete(record)
        #expect(store.pendingDelete?.id == "r1")
        #expect(count(stub, "DELETE") == 0)
        store.cancelDelete()
        #expect(store.pendingDelete == nil)
        #expect(count(stub, "DELETE") == 0)
        store.requestDelete(record)
        await store.confirmDelete()
        #expect(count(stub, "DELETE") == 1)
        #expect(store.records.value?.map(\.id) == ["r2"])
        #expect(store.pendingDelete == nil)
    }

    @Test func confirmDeleteWithoutARequestDoesNothing() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        await store.confirmDelete()
        #expect(count(stub, "DELETE") == 0)
    }

    @Test func toggleProxySendsPatchForA() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let a = try #require(store.records.value?.first)
        await store.toggleProxy(a)
        #expect(count(stub, "PATCH") == 1)
        #expect(store.records.value?.first?.proxied == false)
    }

    @Test func toggleProxyIsRejectedForMX() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let mx = try #require(store.records.value?.last)
        await store.toggleProxy(mx)
        #expect(count(stub, "PATCH") == 0)
        #expect(store.formError == "MX records can't be proxied.")
    }

    @Test func emptyZoneIsLoadedEmpty() async throws {
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(server(records: [])))
        await store.load()
        #expect(store.records.value?.isEmpty == true)
    }

    @Test func permissionDeniedOnListBecomesFailedStateAndKeepsSession() async throws {
        let session = try await TestAPI.readySession(server(listStatus: 403))
        let store = DNSStore(zone: TestAPI.zone, session: session)
        await store.load()
        #expect(store.records.failure == .permissionDenied("Authentication error"))
        #expect(session.state == .ready)
    }

    @Test func unauthorizedOnListSignsOutTheSession() async throws {
        let session = try await TestAPI.readySession(server(listStatus: 401))
        let store = DNSStore(zone: TestAPI.zone, session: session)
        await store.load()
        #expect(session.state == .signedOut)
    }
}
