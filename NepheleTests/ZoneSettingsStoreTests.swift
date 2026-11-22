import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

final class Flag: @unchecked Sendable { var on = false }

@MainActor
@Suite struct ZoneSettingsStoreTests {
    func make(deny: Set<String> = [], patch: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))? = nil, failGet: Flag? = nil) async throws -> (ZoneSettingsStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if req.httpMethod != "GET" {
                if let patch, !p.hasSuffix("/purge_cache") { return patch(req) }
                if deny.contains(where: { p.contains($0) }) { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
                if p.hasSuffix("/purge_cache") { return TestAPI.reply(req, TestAPI.ok("{\"id\":\"p\"}")) }
                let id = p.split(separator: "/").last.map(String.init) ?? ""
                return TestAPI.reply(req, TestAPI.ok("{\"id\":\"\(id)\",\"value\":\"strict\",\"editable\":true}"))
            }
            if p.hasSuffix("/zones/z1/settings"), failGet?.on == true { return TestAPI.reply(req, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"boom\"}],\"result\":null}", status: 500) }
            if p.hasSuffix("/zones/z1/settings") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"ssl\",\"value\":\"full\",\"editable\":true},{\"id\":\"development_mode\",\"value\":\"off\",\"editable\":true}]")) }
            return TestAPI.base(req)
        }
        let store = ZoneSettingsStore(zone: TestAPI.zone, session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }
    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod != "GET" } }

    @Test func loadsSettingsByID() async throws {
        let (s, _) = try await make()
        #expect(s.value("ssl") == "full" && s.value("development_mode") == "off" && s.value("tls_1_3") == nil)
    }

    @Test func changingASettingSendsItAndUpdatesTheValue() async throws {
        let (s, stub) = try await make()
        await s.set("ssl", "strict")
        #expect(s.value("ssl") == "strict" && writes(stub).count == 1 && writes(stub)[0].request.url?.path == "/client/v4/zones/z1/settings/ssl")
    }

    @Test func aForbiddenChangeKeepsTheOldValueAndLocksSettings() async throws {
        let (s, _) = try await make(deny: ["/settings/"])
        await s.set("ssl", "strict")
        #expect(s.value("ssl") == "full" && !s.canChange && s.formError?.contains("Zone Settings Edit") == true)
    }

    @Test func purgeEverythingNeedsTheZoneNameTyped() async throws {
        let (s, stub) = try await make()
        await s.purgeEverything(typedName: "example")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.purgeEverything(typedName: "example.dev")
        #expect(writes(stub).count == 1 && s.formError == nil && s.notice != nil)
    }

    @Test func purgeUrlsValidateBeforeAnyRequest() async throws {
        let (s, stub) = try await make()
        await s.purgeFiles("not a url")
        #expect(s.formError != nil && writes(stub).isEmpty)
        await s.purgeFiles("https://example.dev/a.css")
        #expect(writes(stub).count == 1 && s.notice != nil)
    }

    @Test func aForbiddenPurgeLocksOnlyPurging() async throws {
        let (s, _) = try await make(deny: ["/purge_cache"])
        await s.purgeFiles("https://example.dev/a.css")
        #expect(!s.canPurge && s.canChange && s.formError?.contains("Cache Purge") == true)
    }

    @Test func aLateResultAfterAnAccountSwitchIsIgnored() async throws {
        final class Box: @unchecked Sendable { var session: Session? }
        let box = Box()
        let stub = StubServer { req in
            if req.httpMethod == "PATCH" {
                Task { @MainActor in box.session?.selectAccount("other") }
                Thread.sleep(forTimeInterval: 0.15)
                return TestAPI.reply(req, TestAPI.ok("{\"id\":\"ssl\",\"value\":\"strict\"}"))
            }
            if req.url!.path.hasSuffix("/zones/z1/settings") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"ssl\",\"value\":\"full\"}]")) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub); box.session = session
        let s = ZoneSettingsStore(zone: TestAPI.zone, session: session)
        await s.load()
        await s.set("ssl", "strict")
        #expect(s.value("ssl") == "full")
    }

    @Test func riskyChangesAskFirstAndSafeOnesDont() async throws {
        let (s, stub) = try await make()
        await s.request("ssl", "flexible")
        #expect(writes(stub).isEmpty && s.confirm.pending?.message.contains("redirect") == true)
        await s.confirmChange(try #require(s.confirm.pending))
        #expect(writes(stub).count == 1)
        await s.request("development_mode", "on")
        #expect(writes(stub).count == 2 && s.confirm.pending == nil)
    }

    @Test func aFailedChangeRereadsTheRealValueAndKeepsEditing() async throws {
        let bad: @Sendable (URLRequest) -> (HTTPURLResponse, Data) = { TestAPI.reply($0, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"Bad value\"}],\"result\":null}", status: 400) }
        let (s, stub) = try await make(patch: bad)
        let before = stub.recorded.filter { $0.request.httpMethod == "GET" && $0.request.url?.path.hasSuffix("/zones/z1/settings") == true }.count
        await s.set("ssl", "strict")
        let after = stub.recorded.filter { $0.request.httpMethod == "GET" && $0.request.url?.path.hasSuffix("/zones/z1/settings") == true }.count
        #expect(s.canChange && s.formError == "Bad value" && after == before + 1)
    }

    @Test func aForbiddenReasonThatIsntAboutThePermissionDoesNotLockEverything() async throws {
        let plan: @Sendable (URLRequest) -> (HTTPURLResponse, Data) = { TestAPI.reply($0, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"Not available on your plan\"}],\"result\":null}", status: 403) }
        let (s, _) = try await make(patch: plan)
        await s.set("min_tls_version", "1.3")
        #expect(s.canChange && s.formError == "Not available on your plan")
    }

    @Test func aFailedReloadAfterLoadingIsShown() async throws {
        let flag = Flag()
        let (s, _) = try await make(failGet: flag)
        flag.on = true
        await s.load()
        #expect(s.value("ssl") == "full" && s.formError != nil)
    }
}
