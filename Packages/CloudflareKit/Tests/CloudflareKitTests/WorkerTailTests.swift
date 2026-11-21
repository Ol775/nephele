import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct WorkerTailTests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func tailEventParsesRequestLogsAndExceptions() throws {
        let event = try #require(TailEvent.parse(fixture("tail-events")))
        #expect(event.outcome == "ok")
        #expect(event.method == "GET")
        #expect(event.url == "https://api.example.dev/x")
        #expect(event.logs.count == 1)
        #expect(event.logs[0].level == "log")
        #expect(event.logs[0].text == "hello {\"a\":1}")
        #expect(event.time == Date(timeIntervalSince1970: 1763463602.349))
        #expect(event.isError == false)
    }

    @Test func isErrorTrueForExceptionAndErrorLevelLogAndBadOutcome() throws {
        let withException = Data("{\"outcome\":\"ok\",\"exceptions\":[{\"name\":\"TypeError\",\"message\":\"x is not a function\"}],\"logs\":[],\"eventTimestamp\":1}".utf8)
        let e = try #require(TailEvent.parse(withException))
        #expect(e.isError)
        #expect(e.exceptions == ["TypeError: x is not a function"])
        #expect(try #require(TailEvent.parse(Data("{\"outcome\":\"ok\",\"logs\":[{\"message\":[\"boom\"],\"level\":\"error\",\"timestamp\":1}],\"eventTimestamp\":1}".utf8))).isError)
        #expect(try #require(TailEvent.parse(Data("{\"outcome\":\"exceededCpu\",\"logs\":[],\"eventTimestamp\":1}".utf8))).isError)
    }

    @Test func parseIgnoresMalformedMessage() {
        #expect(TailEvent.parse(Data("not json".utf8)) == nil)
        #expect(TailEvent.parse(Data("[1,2]".utf8)) == nil)
    }

    @Test func startTailDecodesUrlAndId() async throws {
        let stub = StubServer { req in
            (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"id\":\"tail1\",\"url\":\"wss://tail.example.net/abc\",\"expires_at\":\"2026-11-19T12:00:00Z\"}}".utf8))
        }
        let session = try await client(stub).startTail(accountID: "acc1", script: "hello-api")
        #expect(session.id == "tail1")
        #expect(session.url.absoluteString == "wss://tail.example.net/abc")
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.httpMethod == "POST")
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/workers/scripts/hello-api/tails")
    }

    @Test func stopTailDeletesTheSession() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).stopTail(accountID: "acc1", script: "hello-api", id: "tail1")
        #expect(stub.recorded.first?.request.httpMethod == "DELETE")
        #expect(stub.recorded.first?.request.url?.path.hasSuffix("/tails/tail1") == true)
    }
}
