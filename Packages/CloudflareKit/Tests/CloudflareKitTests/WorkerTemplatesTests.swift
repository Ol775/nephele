import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerTemplatesTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    let now = ISO8601DateFormatter().date(from: "2026-11-21T15:30:00Z")!

    @Test func everyTemplateExportsADefaultHandlerObject() {
        #expect(WorkerTemplate.allCases.count == 3)
        for t in WorkerTemplate.allCases {
            #expect(t.source.contains("export default"))
            #expect(t.source.contains("fetch(") || t.source.contains("scheduled("))
            #expect(!t.title.isEmpty)
        }
        #expect(WorkerTemplate.scheduledJob.source.contains("scheduled("))
    }

    @Test func scheduledTemplateCarriesAFiveFieldCron() {
        let cron = WorkerTemplate.scheduledJob.cron
        #expect(cron != nil && validCron(cron!))
        #expect(WorkerTemplate.hello.cron == nil)
    }

    @Test func createValidatesNameThenCreatesWorkerAndUploadsAVersion() async throws {
        let stub = StubServer { req in
            if req.url!.path.hasSuffix("/workers/workers") { return (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"w1\",\"name\":\"new-one\"}}".utf8)) }
            return (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"v1\",\"number\":1}}".utf8))
        }
        let v = try await client(stub).createWorker(accountID: "acc1", name: "new-one", template: .hello, now: now)
        #expect(v.id == "v1")
        #expect(stub.recorded.count == 2)
        #expect(stub.recorded[0].request.url?.path == "/client/v4/accounts/acc1/workers/workers")
        let json = try JSONDecoder().decode(JSONValue.self, from: try #require(stub.recorded[0].body))
        #expect(json["name"] == .string("new-one"))
        #expect(stub.recorded[1].request.url?.path == "/client/v4/accounts/acc1/workers/scripts/new-one/versions")
        #expect(!stub.recorded.contains { $0.request.url!.path.hasSuffix("/deployments") })
        let type = try #require(stub.recorded[1].request.value(forHTTPHeaderField: "Content-Type"))
        let raw = try #require(stub.recorded[1].body)
        let meta = try #require(MultipartForm.parse(raw, contentType: type).first { $0.name == "metadata" })
        let m = try JSONDecoder().decode(JSONValue.self, from: meta.data)
        #expect(m["compatibility_date"] == .string("2026-11-21"))
        #expect(m["annotations"]?["workers/message"] == .string("Created from template: Hello world"))
    }

    @Test func createRejectsInvalidNameBeforeAnyRequest() async {
        let stub = StubServer()
        let c = client(stub)
        let n = now
        await #expect(throws: WorkerValidationError.invalidName) { _ = try await c.createWorker(accountID: "a", name: "Bad_Name", template: .hello, now: n) }
        #expect(stub.recorded.isEmpty)
    }

    @Test func deleteWorkerUsesDeleteWithForce() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteWorker(accountID: "acc1", script: "old-one")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "DELETE")
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/old-one")
        #expect(rec.request.url?.query?.contains("force=true") == true)
    }
}
