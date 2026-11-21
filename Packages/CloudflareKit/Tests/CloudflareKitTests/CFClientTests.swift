import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

struct Item: Codable, Sendable, Equatable { let id: Int }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

func body(_ s: String) -> Data { Data(s.utf8) }
func okList(_ ids: [Int], page: Int = 1, totalPages: Int = 1) -> Data {
    let items = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
    return body("{\"success\":true,\"errors\":[],\"result\":[\(items)],\"result_info\":{\"page\":\(page),\"per_page\":2,\"total_pages\":\(totalPages),\"total_count\":\(totalPages * 2)}}")
}
func page(of request: URLRequest) -> Int {
    let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Int(comps?.queryItems?.first { $0.name == "page" }?.value ?? "") ?? 0
}

@Suite(.serialized) struct CFClientTests {
    let token = "tok_SECRET123"
    func client() -> CFClient { CFClient(token: token, session: StubURLProtocol.session()) }

    @Test func decodesEnvelopeAndSendsBearerHeader() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            (StubURLProtocol.response(req.url!), body("{\"success\":true,\"errors\":[],\"result\":{\"id\":1}}"))
        }
        let env: CFEnvelope<Item> = try await client().get("/things")
        #expect(env.result == Item(id: 1))
        let sent = try #require(StubURLProtocol.recorded.first)
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer tok_SECRET123")
        #expect(sent.request.url?.path == "/client/v4/things")
    }

    @Test func maps401ToUnauthorized() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            (StubURLProtocol.response(req.url!, status: 401), body("{\"success\":false,\"errors\":[{\"code\":9109,\"message\":\"Invalid access token\"}],\"result\":null}"))
        }
        let c = client()
        await #expect(throws: CloudflareError.unauthorized) { let _: CFEnvelope<Item> = try await c.get("/things") }
    }

    @Test func maps403ToPermissionDenied() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            (StubURLProtocol.response(req.url!, status: 403), body("{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error\"}],\"result\":null}"))
        }
        let c = client()
        await #expect(throws: CloudflareError.permissionDenied("Authentication error")) { let _: CFEnvelope<Item> = try await c.get("/things") }
    }

    @Test func retriesOn429HonouringRetryAfter() async throws {
        StubURLProtocol.reset()
        let counter = Counter()
        StubURLProtocol.handler = { req in
            if counter.next() == 1 { return (StubURLProtocol.response(req.url!, status: 429, headers: ["Retry-After": "0"]), body("{}")) }
            return (StubURLProtocol.response(req.url!), body("{\"success\":true,\"errors\":[],\"result\":{\"id\":7}}"))
        }
        let env: CFEnvelope<Item> = try await client().get("/things")
        #expect(env.result == Item(id: 7))
        #expect(StubURLProtocol.recorded.count == 2)
    }

    @Test func givesUpAfterThreeRateLimitRetries() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in (StubURLProtocol.response(req.url!, status: 429, headers: ["Retry-After": "0"]), body("{}")) }
        let c = client()
        await #expect(throws: CloudflareError.rateLimited(retryAfter: 0)) { let _: CFEnvelope<Item> = try await c.get("/things") }
        #expect(StubURLProtocol.recorded.count == 3)
    }

    @Test func getAllFollowsPagination() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            let p = page(of: req)
            return (StubURLProtocol.response(req.url!), okList([p * 10, p * 10 + 1], page: p, totalPages: 3))
        }
        let items: [Item] = try await client().getAll("/things", perPage: 2)
        #expect(items.map(\.id) == [10, 11, 20, 21, 30, 31])
        #expect(StubURLProtocol.recorded.map { page(of: $0.request) } == [1, 2, 3])
        let perPage = URLComponents(url: StubURLProtocol.recorded[0].request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "per_page" }?.value
        #expect(perPage == "2")
    }

    @Test func getAllWithOnePageReturnsThatPage() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in (StubURLProtocol.response(req.url!), okList([1, 2])) }
        let items: [Item] = try await client().getAll("/things", perPage: 2)
        #expect(items.map(\.id) == [1, 2])
        #expect(StubURLProtocol.recorded.count == 1)
    }

    @Test func surfacesApiErrorsFromEnvelope() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            (StubURLProtocol.response(req.url!, status: 400), body("{\"success\":false,\"errors\":[{\"code\":1004,\"message\":\"Bad thing\"}],\"result\":null}"))
        }
        let c = client()
        await #expect(throws: CloudflareError.api(code: 1004, message: "Bad thing")) { let _: CFEnvelope<Item> = try await c.get("/things") }
    }

    @Test func sendPostsJSONBodyAndReturnsResult() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in (StubURLProtocol.response(req.url!), body("{\"success\":true,\"errors\":[],\"result\":{\"id\":5}}")) }
        let out: Item = try await client().send("POST", "/things", body: Item(id: 5))
        #expect(out == Item(id: 5))
        let sent = try #require(StubURLProtocol.recorded.first)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(data: try #require(sent.body), encoding: .utf8) == "{\"id\":5}")
    }

    @Test func graphQLPostsQueryAndUnwrapsData() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in (StubURLProtocol.response(req.url!), body("{\"data\":{\"id\":9},\"errors\":null}")) }
        let out: Item = try await client().graphQL("query { x }")
        #expect(out == Item(id: 9))
        let sent = try #require(StubURLProtocol.recorded.first)
        #expect(sent.request.url?.path == "/client/v4/graphql")
        #expect(String(data: try #require(sent.body), encoding: .utf8)?.contains("query { x }") == true)
    }

    @Test func graphQLAuthorisationErrorsBecomePermissionDenied() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { req in
            (StubURLProtocol.response(req.url!), body("{\"data\":null,\"errors\":[{\"message\":\"zone 'x' does not have access to the path\"}]}"))
        }
        let c = client()
        await #expect(throws: CloudflareError.permissionDenied("zone 'x' does not have access to the path")) { let _: Item = try await c.graphQL("query { x }") }
    }

    @Test func neverLeaksTokenInErrors() async {
        var collected: [CloudflareError] = []
        let cases: [(Int, String, [String: String])] = [
            (401, "{\"success\":false,\"errors\":[{\"code\":9109,\"message\":\"Invalid\"}]}", [:]),
            (403, "{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Denied\"}]}", [:]),
            (429, "{}", ["Retry-After": "0"]),
            (400, "{\"success\":false,\"errors\":[{\"code\":1004,\"message\":\"Bad\"}]}", [:]),
            (200, "not json at all", [:]),
        ]
        for (status, payload, headers) in cases {
            StubURLProtocol.reset()
            StubURLProtocol.handler = { req in (StubURLProtocol.response(req.url!, status: status, headers: headers), body(payload)) }
            do { let _: CFEnvelope<Item> = try await client().get("/things") } catch let e as CloudflareError { collected.append(e) } catch {}
        }
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { let _: CFEnvelope<Item> = try await client().get("/things") } catch let e as CloudflareError { collected.append(e) } catch {}
        #expect(collected.count == 6)
        for e in collected {
            #expect(!String(describing: e).contains("tok_SECRET123"))
            #expect(!e.localizedDescription.contains("tok_SECRET123"))
        }
    }
}
