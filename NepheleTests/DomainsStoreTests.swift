import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct DomainsStoreTests {
    func zoneRequests(_ stub: StubServer) -> Int { stub.recorded.filter { $0.request.url!.path.hasSuffix("/zones") && $0.request.url?.query?.contains("per_page=50") == true }.count }

    @Test func loadWithinTTLDoesNotRefetch() async throws {
        let stub = StubServer { TestAPI.base($0) }
        let store = DomainsStore(session: try await TestAPI.readySession(stub), ttl: 60)
        await store.load()
        let after = zoneRequests(stub)
        await store.load()
        #expect(zoneRequests(stub) == after)
        #expect(store.zones.value?.map(\.name) == ["example.dev"])
    }

    @Test func forceReloadRefetches() async throws {
        let stub = StubServer { TestAPI.base($0) }
        let store = DomainsStore(session: try await TestAPI.readySession(stub), ttl: 60)
        await store.load()
        let after = zoneRequests(stub)
        await store.load(force: true)
        #expect(zoneRequests(stub) == after + 1)
    }

    @Test func expiredTTLRefetches() async throws {
        let stub = StubServer { TestAPI.base($0) }
        var now = Date(timeIntervalSince1970: 1_000)
        let box = ClockBox(now)
        let store = DomainsStore(session: try await TestAPI.readySession(stub), ttl: 60, now: { box.value })
        await store.load()
        let after = zoneRequests(stub)
        now.addTimeInterval(61); box.value = now
        await store.load()
        #expect(zoneRequests(stub) == after + 1)
    }

    @Test func permissionDeniedBecomesFailedStateNotCrash() async throws {
        let stub = StubServer { req in
            if req.url!.path.hasSuffix("/zones"), req.url?.query?.contains("per_page=50") == true { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let store = DomainsStore(session: session)
        await store.load()
        #expect(store.zones.failure == .permissionDenied("Authentication error"))
        #expect(session.state == .ready)
    }

    @Test func emptyZonesIsLoadedEmpty() async throws {
        let stub = StubServer { req in
            if req.url!.path.hasSuffix("/zones"), req.url?.query?.contains("per_page=50") == true { return TestAPI.reply(req, TestAPI.ok("[]")) }
            return TestAPI.base(req)
        }
        let store = DomainsStore(session: try await TestAPI.readySession(stub))
        await store.load()
        #expect(store.zones.value?.isEmpty == true)
    }

    @Test func failedRefreshKeepsPreviouslyLoadedZones() async throws {
        nonisolated(unsafe) var failing = false
        let stub = StubServer { req in
            if failing, req.url!.path.hasSuffix("/zones"), req.url?.query?.contains("per_page=50") == true { throw URLError(.notConnectedToInternet) }
            return TestAPI.base(req)
        }
        let store = DomainsStore(session: try await TestAPI.readySession(stub))
        await store.load()
        failing = true
        await store.load(force: true)
        #expect(store.zones.value?.count == 1)
        #expect(store.lastError != nil)
    }

    @Test func sessionClearCacheForcesNextLoadToRefetch() async throws {
        let stub = StubServer { TestAPI.base($0) }
        let session = try await TestAPI.readySession(stub)
        let store = DomainsStore(session: session, ttl: 60)
        await store.load()
        let after = zoneRequests(stub)
        session.clearCache()
        await store.load()
        #expect(zoneRequests(stub) == after + 1)
    }

    @Test func resetForgetsEverythingLoaded() async throws {
        let stub = StubServer { TestAPI.base($0) }
        let store = DomainsStore(session: try await TestAPI.readySession(stub), ttl: 60)
        await store.load()
        store.reset()
        #expect(store.zones.value == nil)
        let before = zoneRequests(stub)
        await store.load()
        #expect(zoneRequests(stub) == before + 1)
    }

    @Test func clearCacheForcesNextLoadToRefetch() async throws {
        let stub = StubServer { TestAPI.base($0) }
        let store = DomainsStore(session: try await TestAPI.readySession(stub), ttl: 60)
        await store.load()
        let after = zoneRequests(stub)
        store.clearCache()
        await store.load()
        #expect(zoneRequests(stub) == after + 1)
    }
}

final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ v: Date) { _value = v }
    var value: Date { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
