import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct PagesStoreTests {
    func make(denyWrites: Bool = false) async throws -> (PagesStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if denyWrites && req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            if req.httpMethod != "GET" { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"x\"}")) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"d2\",\"environment\":\"production\",\"latest_stage\":{\"status\":\"success\"}},{\"id\":\"d1\",\"environment\":\"preview\",\"latest_stage\":{\"status\":\"failure\"}}]")) }
            if p.hasSuffix("/pages/projects") { return TestAPI.reply(req, TestAPI.ok("[{\"name\":\"zed\"},{\"name\":\"site\"}]")) }
            return TestAPI.base(req)
        }
        let store = PagesStore(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }
    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsProjectsSortedAndDeploymentsOnSelect() async throws {
        let (s, _) = try await make()
        #expect(s.projects.value?.map(\.name) == ["site", "zed"])
        await s.select(s.projects.value?.first)
        #expect(s.deployments.value?.map(\.id) == ["d2", "d1"])
    }

    @Test func rollbackAndRetryNeedConfirmationAndSendOnce() async throws {
        let (s, stub) = try await make()
        await s.select(s.projects.value?.first)
        s.request(.rollback(try #require(s.deployments.value?.last)))
        #expect(writes(stub).isEmpty)
        let pending = try #require(s.confirm.pending)
        #expect(pending.message(project: "site").contains("site"))
        await s.confirmChange(pending); await s.confirmChange(pending)
        #expect(writes(stub).count == 1 && writes(stub)[0].request.url?.path.hasSuffix("/d1/rollback") == true)
    }

    @Test func deleteDeploymentRemovesItAndFailureKeepsIt() async throws {
        let (s, stub) = try await make()
        await s.select(s.projects.value?.first)
        let d = try #require(s.deployments.value?.last)
        s.request(.delete(d)); await s.confirmChange(try #require(s.confirm.pending))
        #expect(s.deployments.value?.map(\.id) == ["d2"] && writes(stub).count == 1)
    }

    @Test func projectDeleteNeedsTheTypedName() async throws {
        let (s, stub) = try await make()
        let p = try #require(s.projects.value?.first)
        await s.deleteProject(p, typedName: "sit")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.deleteProject(p, typedName: "site")
        #expect(s.projects.value?.map(\.name) == ["zed"])
    }

    @Test func forbiddenWriteTurnsWritesOffAndKeepsTheList() async throws {
        let (s, _) = try await make(denyWrites: true)
        await s.select(s.projects.value?.first)
        s.request(.retry(try #require(s.deployments.value?.first))); await s.confirmChange(try #require(s.confirm.pending))
        #expect(!s.canWrite && s.formError?.contains("Pages Edit") == true && s.deployments.value?.count == 2)
    }

    @Test func resetClears() async throws {
        let (s, _) = try await make()
        await s.select(s.projects.value?.first); s.reset()
        #expect(s.projects.value == nil && s.selected == nil && s.deployments.value == nil && s.canWrite)
    }

    @Test func deleteOfAnAliasedPreviewSendsForce() async throws {
        let stub = StubServer { req in
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if req.url!.path.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"d1\",\"environment\":\"preview\",\"aliases\":[\"feat.site.pages.dev\"]}]")) }
            if req.url!.path.hasSuffix("/pages/projects") { return TestAPI.reply(req, TestAPI.ok("[{\"name\":\"site\",\"canonical_deployment\":{\"id\":\"live\"}}]")) }
            return TestAPI.base(req)
        }
        let s = PagesStore(session: try await TestAPI.readySession(stub))
        await s.load(); await s.select(s.projects.value?.first)
        let d = try #require(s.deployments.value?.first)
        s.request(.delete(d))
        #expect(s.confirm.pending?.message(project: "site").contains("feat.site.pages.dev") == true)
        await s.confirmChange(try #require(s.confirm.pending))
        #expect(stub.recorded.last?.request.url?.query == "force=true")
        #expect(s.isLive(PagesDeployment(id: "live")) && !s.isLive(d))
    }

    @Test func lateDeleteDoesNotTouchAnotherProjectsList() async throws {
        final class Box: @unchecked Sendable { var store: PagesStore? }
        let box = Box()
        let stub = StubServer { req in
            let p = req.url!.path
            if req.httpMethod == "DELETE" {
                Task { @MainActor in await box.store?.select(box.store?.projects.value?.last) }
                Thread.sleep(forTimeInterval: 0.15)
                return TestAPI.reply(req, TestAPI.ok("null"))
            }
            if p.hasSuffix("/projects/zed/deployments") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"z1\"}]")) }
            if p.hasSuffix("/deployments") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"d1\"},{\"id\":\"d2\"}]")) }
            if p.hasSuffix("/pages/projects") { return TestAPI.reply(req, TestAPI.ok("[{\"name\":\"site\"},{\"name\":\"zed\"}]")) }
            return TestAPI.base(req)
        }
        let s = PagesStore(session: try await TestAPI.readySession(stub)); box.store = s
        await s.load(); await s.select(s.projects.value?.first)
        s.request(.delete(try #require(s.deployments.value?.first)))
        await s.confirmChange(try #require(s.confirm.pending))
        try await Task.sleep(for: .milliseconds(300))
        #expect(s.selected?.name == "zed" && s.deployments.value?.map(\.id) == ["z1"])
    }

    @Test func aFailedWriteErrorBelongsToItsProject() async throws {
        let (s, _) = try await make(denyWrites: true)
        await s.deleteProject(try #require(s.projects.value?.last), typedName: "zed")
        #expect(s.formErrorProject == "zed")
        await s.select(s.projects.value?.first)
        #expect(s.formError == nil)
    }
}
