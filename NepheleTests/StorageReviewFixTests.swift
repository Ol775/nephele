import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

/// Regression tests for the storage review's Critical and Important findings.
final class Gate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock(); private var _armed = false
    var armed: Bool { get { lock.withLock { _armed } } set { lock.withLock { _armed = newValue } } }
    func waitEntered() async { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.global().async { self.entered.wait(); c.resume() } } }
}

@MainActor
@Suite struct StorageReviewFixTests {
    nonisolated static let namespaces = "[{\"id\":\"ns1\",\"title\":\"PROD\"},{\"id\":\"ns2\",\"title\":\"STAGING\"}]"

    func kv(gate: Gate = Gate(), keys: String = "[{\"name\":\"config\",\"expiration\":1900000000},{\"name\":\"tagged\",\"metadata\":{\"x\":1}}]",
            existing: Set<String> = ["config", "tagged"]) async throws -> (KVStore, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if gate.armed && p.contains("/values/") && req.httpMethod == "GET" { gate.entered.signal(); gate.release.wait() }
            if gate.armed && req.httpMethod == "POST" && p.hasSuffix("/kv/namespaces") { gate.entered.signal(); gate.release.wait(); return TestAPI.reply(req, TestAPI.ok("{\"id\":\"nsX\",\"title\":\"late\"}")) }
            if req.httpMethod == "PUT" || req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if p.hasSuffix("/keys") { return TestAPI.reply(req, "{\"success\":true,\"errors\":[],\"result\":\(keys),\"result_info\":{\"count\":2,\"cursor\":\"\"}}") }
            if p.contains("/values/") {
                let key = p.split(separator: "/").last.map(String.init) ?? ""
                return existing.contains(key) ? (StubURLProtocol.response(req.url!), Data("value".utf8)) : TestAPI.reply(req, TestAPI.forbiddenBody.replacingOccurrences(of: "10000", with: "10009"), status: 404)
            }
            if p.hasSuffix("/kv/namespaces") { return TestAPI.reply(req, TestAPI.ok(Self.namespaces)) }
            return TestAPI.base(req)
        }
        let store = KVStore(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    func writes(_ stub: StubServer) -> [StubServer.Recorded] { stub.recorded.filter { $0.request.httpMethod == "PUT" || $0.request.httpMethod == "DELETE" || $0.request.httpMethod == "POST" } }

    // C2
    @Test func aValueThatLoadsAfterSwitchingNamespaceIsDroppedAndNeverSavedElsewhere() async throws {
        let gate = Gate()
        let (store, stub) = try await kv(gate: gate)
        await store.select(store.namespaces.value?.first { $0.title == "PROD" })
        let key = try #require(store.keys.first)
        gate.armed = true
        let opening = Task { await store.open(key) }
        await gate.waitEntered()
        gate.armed = false
        // The stub's blocked request also blocks later ones, so start the switch, let it set `selected`, then release.
        let switching = Task { await store.select(store.namespaces.value?.first { $0.title == "STAGING" }) }
        try await Task.sleep(for: .milliseconds(100))
        gate.release.signal()
        await switching.value
        await opening.value
        #expect(store.draft == "")
        #expect(store.value.value == nil)
        await store.saveValue()
        #expect(writes(stub).isEmpty)
    }

    // C3
    @Test func addingAnExistingKeyIsRefusedAndAnewKeyIsWritten() async throws {
        let (store, stub) = try await kv()
        await store.select(store.namespaces.value?.first)
        await store.addKey("config", value: "")
        #expect(store.formError?.contains("already exists") == true)
        #expect(writes(stub).isEmpty)
        store.formError = nil
        await store.addKey("brand-new", value: "")
        #expect(writes(stub).count == 1)
        #expect(store.keys.map(\.name).contains("brand-new"))
    }

    // I1
    @Test func savingKeepsTheKeysExpiration() async throws {
        let (store, stub) = try await kv()
        await store.select(store.namespaces.value?.first)
        await store.open(try #require(store.keys.first { $0.name == "config" }))
        store.draft = "changed"
        await store.saveValue()
        #expect(writes(stub).first?.request.url?.query?.contains("expiration=1900000000") == true)
    }

    @Test func aKeyWithMetadataIsReadOnlyBecauseASaveWouldErasIt() async throws {
        let (store, stub) = try await kv()
        await store.select(store.namespaces.value?.first)
        await store.open(try #require(store.keys.first { $0.name == "tagged" }))
        #expect(store.editBlockedReason != nil)
        store.draft = "changed"
        await store.saveValue()
        #expect(writes(stub).isEmpty)
    }

    // I4
    @Test func aNamespaceCreatedAfterAnAccountSwitchIsNotAddedToTheNewList() async throws {
        let gate = Gate()
        let (store, _) = try await kv(gate: gate)
        gate.armed = true
        let creating = Task { await store.createNamespace("late") }
        await gate.waitEntered()
        store.session.selectAccount("accB"); store.reset()
        gate.release.signal()
        await creating.value
        #expect(store.namespaces.value == nil)
    }

    // I2 / I3
    func d1(gate: Gate = Gate()) async throws -> (D1Store, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            if p.hasSuffix("/raw") {
                let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
                if gate.armed && body.contains("SLOW") { gate.entered.signal(); gate.release.wait() }
                return TestAPI.reply(req, TestAPI.ok("[{\"results\":{\"columns\":[\"name\"],\"rows\":[[\"t\"]]},\"meta\":{\"rows_read\":1,\"rows_written\":0,\"duration\":0.1}}]"))
            }
            if p.hasSuffix("/d1/database") { return TestAPI.reply(req, TestAPI.ok("[{\"uuid\":\"db-1\",\"name\":\"prod\"},{\"uuid\":\"db-2\",\"name\":\"staging\"}]")) }
            return TestAPI.base(req)
        }
        let store = D1Store(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    @Test func aD1ResultFromTheOldDatabaseIsDroppedAfterSwitching() async throws {
        let gate = Gate()
        let (store, _) = try await d1(gate: gate)
        await store.select(store.databases.value?.first { $0.name == "prod" })
        store.sql = "SELECT 'SLOW'"
        gate.armed = true
        let running = Task { await store.run() }
        await gate.waitEntered()
        gate.armed = false
        let switching = Task { await store.select(store.databases.value?.first { $0.name == "staging" }) }
        try await Task.sleep(for: .milliseconds(100))
        gate.release.signal()
        await switching.value
        await running.value
        if case .loaded = store.results { Issue.record("stale result shown under the other database") }
    }

    @Test func aConfirmedWriteKeepsTheStatementInTheEditor() async throws {
        let (store, _) = try await d1()
        await store.select(store.databases.value?.first)
        store.sql = "UPDATE t SET a = 1"
        await store.run()
        await store.confirmWrite(try #require(store.confirm.pending))
        #expect(store.sql == "UPDATE t SET a = 1")
        #expect(store.results.value != nil)
    }

    // I4 (R2)
    @Test func anR2BucketCreatedAfterAnAccountSwitchIsNotAddedToTheNewList() async throws {
        let gate = Gate()
        let stub = StubServer { req in
            if gate.armed && req.httpMethod == "POST" { gate.entered.signal(); gate.release.wait(); return TestAPI.reply(req, TestAPI.ok("{\"name\":\"late-one\"}")) }
            if req.url!.path.hasSuffix("/r2/buckets") { return TestAPI.reply(req, TestAPI.ok("{\"buckets\":[]}")) }
            return TestAPI.base(req)
        }
        let store = R2Store(session: try await TestAPI.readySession(stub))
        await store.load()
        gate.armed = true
        let creating = Task { await store.create("late-one") }
        await gate.waitEntered()
        store.session.selectAccount("accB"); store.reset()
        gate.release.signal()
        await creating.value
        #expect(store.buckets.value == nil)
    }

    // M9: the screens themselves
    @Test func theD1AndR2ScreensRender() async throws {
        let w = try await ViewSmokeTests().world()
        #expect(try ViewSmokeTests().render("d1-view", D1View(), w) > 5_000)
        #expect(try ViewSmokeTests().render("r2-view", R2View(), w) > 5_000)
    }
}
