import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct TailStoreTests {
    nonisolated static func event(outcome: String = "ok", log: String? = nil, level: String = "log", n: Int = 1) -> Data {
        let logs = log.map { "[{\"message\":[\"\($0)\"],\"level\":\"\(level)\",\"timestamp\":\(n)}]" } ?? "[]"
        return Data("{\"outcome\":\"\(outcome)\",\"logs\":\(logs),\"exceptions\":[],\"eventTimestamp\":\(n * 1000),\"event\":{\"request\":{\"url\":\"https://x.example.dev/\(n)\",\"method\":\"GET\"}}}".utf8)
    }

    func make(start: String = TestAPI.ok("{\"id\":\"tail1\",\"url\":\"wss://tail.example.net/abc\"}"), startStatus: Int = 200,
              messages: [Data]) async throws -> (TailStore, StubServer) {
        let stub = StubServer { req in
            if req.httpMethod == "POST" && req.url!.path.hasSuffix("/tails") { return TestAPI.reply(req, start, status: startStatus) }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let store = TailStore(session: session, script: "hello-api", openSocket: { _ in AsyncStream { c in messages.forEach { c.yield($0) }; c.finish() } })
        return (store, stub)
    }

    @Test func runConnectsAndAppendsEvents() async throws {
        let (store, stub) = try await make(messages: [Self.event(n: 1), Self.event(n: 2)])
        await store.run()
        #expect(store.events.count == 2)
        #expect(store.events.map(\.url) == ["https://x.example.dev/1", "https://x.example.dev/2"])
        #expect(stub.recorded.contains { $0.request.httpMethod == "POST" })
    }

    @Test func errorsOnlyFiltersVisibleEvents() async throws {
        let (store, _) = try await make(messages: [Self.event(n: 1), Self.event(log: "boom", level: "error", n: 2), Self.event(outcome: "exception", n: 3)])
        await store.run()
        #expect(store.visibleEvents.count == 3)
        store.errorsOnly = true
        #expect(store.visibleEvents.count == 2)
    }

    @Test func bufferIsCappedAtFiveHundredDroppingOldest() async throws {
        let (store, _) = try await make(messages: (1...520).map { Self.event(n: $0) })
        await store.run()
        #expect(store.events.count == 500)
        #expect(store.events.first?.url == "https://x.example.dev/21")
    }

    @Test func stopCallsStopTailOnce() async throws {
        let (store, stub) = try await make(messages: [Self.event()])
        await store.run()
        await store.stop()
        await store.stop()
        #expect(stub.recorded.filter { $0.request.httpMethod == "DELETE" }.count == 1)
        #expect(store.state == .stopped(nil))
    }

    @Test func samplingMessageSetsNotice() async throws {
        let (store, _) = try await make(messages: [Data("{\"message\":\"Tail is sampling: some events were dropped\"}".utf8), Self.event()])
        await store.run()
        #expect(store.samplingNotice)
        #expect(store.events.count == 1)
    }

    @Test func startFailureShowsFriendlyMessage() async throws {
        let body = "{\"success\":false,\"errors\":[{\"code\":10057,\"message\":\"Too many tail sessions already open for this script\"}],\"result\":null}"
        let (store, _) = try await make(start: body, startStatus: 400, messages: [])
        await store.run()
        guard case .stopped(let reason?) = store.state else { Issue.record("expected stopped with a reason"); return }
        #expect(reason.contains("Too many people"))
    }

    @Test func forbiddenStartExplainsThePermission() async throws {
        let (store, _) = try await make(start: TestAPI.forbiddenBody, startStatus: 403, messages: [])
        await store.run()
        guard case .stopped(let reason?) = store.state else { Issue.record("expected stopped with a reason"); return }
        #expect(reason.contains("Workers Tail Read"))
    }
}
