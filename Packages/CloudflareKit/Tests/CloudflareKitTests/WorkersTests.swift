import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkersTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func workersDecodesFixture() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("workers-list")) }
        let scripts = try await client(stub).workers(accountID: "acc1")
        #expect(scripts.map(\.id) == ["hello-api", "cron-job"])
        #expect(scripts[0].modifiedOn != nil)
        #expect(scripts[0].compatibilityDate == "2026-10-01")
        #expect(scripts[1].handlers == ["scheduled"])
    }

    @Test func workersRequestPathIsAccountScripts() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("workers-list")) }
        _ = try await client(stub).workers(accountID: "acc1")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/workers/scripts")
    }

    @Test func deploymentsDecodeNewestFirst() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("workers-deployments")) }
        let list = try await client(stub).deployments(accountID: "acc1", script: "hello-api")
        #expect(list.map(\.id) == ["d2", "d1"])
        #expect(list[0].message == "Fix timeout")
        #expect(list[0].versions == [DeploymentVersion(versionId: "v-0002-aaaa", percentage: 100)])
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/deployments")
    }
}
