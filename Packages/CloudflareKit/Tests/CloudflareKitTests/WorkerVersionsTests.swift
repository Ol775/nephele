import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerVersionsTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func versionsDecodeNewestFirst() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-versions")) }
        let list = try await client(stub).workerVersions(accountID: "acc1", script: "hello-api")
        #expect(list.map(\.id) == ["v-0002-aaaa", "v-0001-bbbb"])
        #expect(list[0].number == 2)
        #expect(list[0].message == "Fix timeout")
        #expect(list[1].message == nil)
        #expect(list[0].authorEmail == "dev@example.dev")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/versions")
    }

    @Test func deployBodyIsHundredPercentSingleVersion() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("worker-deployment-created")) }
        let d = try await client(stub).deployVersion(accountID: "acc1", script: "hello-api", versionID: "v-0001-bbbb", message: "Rolled back")
        #expect(d.id == "d3")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "POST")
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/deployments")
        let raw = try #require(rec.body)
        let json = try JSONDecoder().decode(JSONValue.self, from: raw)
        #expect(json["strategy"] == .string("percentage"))
        #expect(json["versions"] == .array([.object(["percentage": .number(100), "version_id": .string("v-0001-bbbb")])]))
        #expect(json["annotations"]?["workers/message"] == .string("Rolled back"))
    }

    @Test func messageLongerThan1000BytesIsRejectedBeforeSending() async {
        let stub = StubServer()
        let c = client(stub)
        let long = String(repeating: "é", count: 501)   // 1002 bytes
        await #expect(throws: WorkerValidationError.messageTooLong) {
            _ = try await c.deployVersion(accountID: "acc1", script: "s", versionID: "v", message: long)
        }
        #expect(stub.recorded.isEmpty)
    }
}
