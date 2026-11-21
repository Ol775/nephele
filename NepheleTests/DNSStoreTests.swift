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
        let action = try #require(store.pending)
        #expect(action.kind == .delete && action.record.id == "r1")
        #expect(count(stub, "DELETE") == 0)
        store.cancel()
        #expect(store.pending == nil)
        await store.confirm(action)
        #expect(count(stub, "DELETE") == 0)
        store.requestDelete(record)
        await store.confirm(try #require(store.pending))
        #expect(count(stub, "DELETE") == 1)
        #expect(store.records.value?.map(\.id) == ["r2"])
        #expect(store.pending == nil)
    }

    @Test func confirmStillWorksAfterTheDialogIsDismissedByTheSystem() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        store.requestDelete(try #require(store.records.value?.first))
        let action = try #require(store.pending)
        store.dialogDismissed()
        #expect(store.pending == nil)
        await store.confirm(action)
        #expect(count(stub, "DELETE") == 1)
    }

    @Test func confirmingSomethingNeverRequestedDoesNothing() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let record = try #require(store.records.value?.first)
        await store.confirm(PendingAction(kind: .delete, record: record))
        #expect(count(stub, "DELETE") == 0)
    }

    @Test func proxyChangeNeedsConfirmationThenSendsPatch() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        store.requestProxyToggle(try #require(store.records.value?.first))
        let action = try #require(store.pending)
        #expect(action.kind == .proxy)
        #expect(count(stub, "PATCH") == 0)
        await store.confirm(action)
        #expect(count(stub, "PATCH") == 1)
        #expect(store.records.value?.first?.proxied == false)
    }

    @Test func proxyChangeIsRejectedForMXWithoutAskingToConfirm() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        store.requestProxyToggle(try #require(store.records.value?.last))
        #expect(store.pending == nil)
        #expect(count(stub, "PATCH") == 0)
        #expect(store.formError == "MX records can't be proxied.")
    }

    @Test func updateSendsAPatchWithTheValidatedDraft() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let record = try #require(store.records.value?.first)
        await store.update(record, with: DNSRecordDraft(type: "A", name: "EXAMPLE.dev", content: "192.0.2.99", proxied: true, ttl: 300))
        #expect(count(stub, "PATCH") == 1)
        let sent = try #require(stub.recorded.last { $0.request.httpMethod == "PATCH" })
        let raw = try #require(sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(json["content"] as? String == "192.0.2.99")
        #expect(json["ttl"] as? Int == 300)
        #expect(json["name"] as? String == "example.dev")
        #expect(store.formError == nil)
    }

    @Test func invalidEditSetsAnErrorAndSendsNothing() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        let record = try #require(store.records.value?.first)
        await store.update(record, with: DNSRecordDraft(type: "A", name: "@", content: "not an ip", proxied: true))
        #expect(store.formError == "An A record needs an IPv4 address, such as 192.0.2.10.")
        #expect(count(stub, "PATCH") == 0)
    }

    @Test func addPassesTheProxiedChoiceThrough() async throws {
        let stub = server()
        let store = DNSStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.add(DNSRecordDraft(type: "A", name: "mail", content: "192.0.2.55", proxied: false))
        let sent = try #require(stub.recorded.last { $0.request.httpMethod == "POST" })
        let raw = try #require(sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(json["proxied"] as? Bool == false)
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
