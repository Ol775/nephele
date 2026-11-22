import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct PagesTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }
    static let projects = "{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"site\",\"subdomain\":\"site.pages.dev\",\"domains\":[\"site.pages.dev\",\"example.dev\"],\"production_branch\":\"main\",\"created_on\":\"2026-05-01T10:00:00.000Z\",\"latest_deployment\":{\"id\":\"d1\",\"short_id\":\"abc123\",\"environment\":\"production\",\"url\":\"https://abc123.site.pages.dev\",\"created_on\":\"2026-11-20T10:00:00.000Z\",\"latest_stage\":{\"name\":\"deploy\",\"status\":\"success\"},\"deployment_trigger\":{\"metadata\":{\"branch\":\"main\",\"commit_message\":\"Fix header\",\"commit_hash\":\"deadbeefcafe\"}}}},{\"name\":\"bare\"}],\"result_info\":{\"page\":1,\"per_page\":10,\"total_pages\":1,\"count\":2,\"total_count\":2}}"

    @Test func projectsDecodeWithLatestDeploymentAndTolerateBareOnes() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data(Self.projects.utf8)) }
        let list = try await client(stub).pagesProjects(accountID: "acc1")
        #expect(list.map(\.name) == ["site", "bare"])
        let d = try #require(list[0].latestDeployment)
        #expect(d.environment == "production" && d.latestStage?.status == "success" && d.trigger?.branch == "main" && d.trigger?.commitMessage == "Fix header")
        #expect(list[0].domains == ["site.pages.dev", "example.dev"] && list[1].domains == nil && list[1].latestDeployment == nil)
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/pages/projects")
    }

    @Test func deploymentsListPerProjectAndEncodeTheName() async throws {
        let body = "{\"success\":true,\"errors\":[],\"result\":[{\"id\":\"d1\",\"environment\":\"preview\",\"created_on\":\"2026-11-20T10:00:00Z\",\"latest_stage\":{\"name\":\"build\",\"status\":\"failure\"}}],\"result_info\":{\"page\":1,\"per_page\":25,\"total_pages\":1,\"count\":1,\"total_count\":1}}"
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data(body.utf8)) }
        let list = try await client(stub).pagesDeployments(accountID: "acc1", project: "my/site")
        #expect(list[0].latestStage?.status == "failure" && list[0].trigger == nil)
        #expect(stub.recorded.first?.request.url?.absoluteString.contains("/projects/my%2Fsite/deployments") == true)
    }

    @Test func retryRollbackAndDeletesUseTheRightVerbsAndPaths() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"d2\"}}".utf8)) }
        let c = client(stub)
        try await c.retryPagesDeployment(accountID: "acc1", project: "site", id: "d1")
        try await c.rollbackPagesDeployment(accountID: "acc1", project: "site", id: "d1")
        try await c.deletePagesDeployment(accountID: "acc1", project: "site", id: "d1")
        try await c.deletePagesProject(accountID: "acc1", name: "site")
        let r = stub.recorded.map { ($0.request.httpMethod ?? "", $0.request.url?.path ?? "") }
        #expect(r[0] == ("POST", "/client/v4/accounts/acc1/pages/projects/site/deployments/d1/retry"))
        #expect(r[1].1.hasSuffix("/d1/rollback") && r[1].0 == "POST")
        #expect(r[2] == ("DELETE", "/client/v4/accounts/acc1/pages/projects/site/deployments/d1"))
        #expect(r[3] == ("DELETE", "/client/v4/accounts/acc1/pages/projects/site"))
    }

    @Test func aliasesAndCanonicalDeploymentDecodeAndForceAddsTheQuery() async throws {
        let body = "{\"success\":true,\"errors\":[],\"result\":[{\"name\":\"site\",\"canonical_deployment\":{\"id\":\"live1\"}}],\"result_info\":{\"page\":1,\"per_page\":10,\"total_pages\":1,\"count\":1,\"total_count\":1}}"
        let dep = "{\"success\":true,\"errors\":[],\"result\":[{\"id\":\"d1\",\"aliases\":[\"feat.site.pages.dev\"]}]}"
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data((req.url!.path.hasSuffix("/projects") ? body : dep).utf8)) }
        let c = client(stub)
        #expect(try await c.pagesProjects(accountID: "a")[0].canonicalDeploymentID == "live1")
        #expect(try await c.pagesDeployments(accountID: "a", project: "site")[0].aliases == ["feat.site.pages.dev"])
        let del = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(del).deletePagesDeployment(accountID: "a", project: "site", id: "d1", force: true)
        try await client(del).deletePagesDeployment(accountID: "a", project: "site", id: "d1")
        #expect(del.recorded[0].request.url?.query == "force=true" && del.recorded[1].request.url?.query == nil)
    }
}
