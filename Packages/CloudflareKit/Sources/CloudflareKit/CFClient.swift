import Foundation

struct AnyEncodable: Encodable {
    let value: any Encodable
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: AnyEncodable?
}

private struct GraphQLResponse<T: Decodable & Sendable>: Decodable, Sendable {
    struct Failure: Decodable, Sendable { let message: String }
    let data: T?
    let errors: [Failure]?
}

public actor CFClient {
    private let token: String
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private static let maxAttempts = 3

    public init(token: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
    }

    public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> CFEnvelope<T> {
        let (data, status, _) = try await perform("GET", path, query: query, body: nil)
        return try decodeEnvelope(data, status: status)
    }

    public func getAll<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], perPage: Int) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while page <= 1000 {
            let q = query + [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
            let env: CFEnvelope<[T]> = try await get(path, query: q)
            all += env.result ?? []
            if page >= (env.resultInfo?.totalPages ?? 1) { break }
            page += 1
        }
        return all
    }

    public func send<T: Decodable & Sendable>(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil) async throws -> T {
        let data = try body.map { try encoder.encode(AnyEncodable(value: $0)) }
        let (response, status, _) = try await perform(method, path, query: [], body: data)
        let env: CFEnvelope<T> = try decodeEnvelope(response, status: status)
        guard let result = env.result else { throw CloudflareError.decoding("Missing result") }
        return result
    }

    public func graphQL<T: Decodable & Sendable>(_ query: String, variables: (any Encodable & Sendable)? = nil) async throws -> T {
        let payload = try encoder.encode(GraphQLRequest(query: query, variables: variables.map { AnyEncodable(value: $0) }))
        let (data, status, _) = try await perform("POST", "/graphql", query: [], body: payload)
        if status == 401 { throw CloudflareError.unauthorized }
        do {
            let response = try decoder.decode(GraphQLResponse<T>.self, from: data)
            if let first = response.errors?.first, response.data == nil {
                let m = first.message.lowercased()
                if m.contains("not authorized") || m.contains("does not have access") || m.contains("permission") {
                    throw CloudflareError.permissionDenied(first.message)
                }
                throw CloudflareError.api(code: 0, message: first.message)
            }
            guard let value = response.data else { throw CloudflareError.decoding("Missing data") }
            return value
        } catch let e as CloudflareError { throw e }
        catch { throw CloudflareError.decoding(String(describing: type(of: error))) }
    }

    /// Sends a request and returns the whole validated response body, so callers can decode it with their own
    /// `JSONDecoder` (no key conversion: binding field names survive exactly).
    public func raw(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        let (data, status, _) = try await perform(method, path, query: query, body: body, contentType: contentType)
        let _: CFEnvelope<JSONValue> = try decodeEnvelope(data, status: status)
        return data
    }

    /// GET for a response that is not a Cloudflare envelope (script content). Header names come back lowercased.
    public func download(_ path: String) async throws -> (data: Data, headers: [String: String]) {
        let (data, status, headers) = try await perform("GET", path, query: [], body: nil)
        switch status {
        case 200..<300: return (data, headers)
        case 401: throw CloudflareError.unauthorized
        case 403: throw CloudflareError.permissionDenied(nil)
        default: throw CloudflareError.transport("HTTP \(status)")
        }
    }

    // MARK: - Transport

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, contentType: String = "application/json") async throws -> (Data, Int, [String: String]) {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        var delay: TimeInterval = 1
        for attempt in 1...Self.maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 429 {
                    let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                    if attempt == Self.maxAttempts { throw CloudflareError.rateLimited(retryAfter: retryAfter) }
                    try await sleep(retryAfter ?? delay)
                    delay *= 2
                    continue
                }
                var headers: [String: String] = [:]
                for (k, v) in http?.allHeaderFields ?? [:] { if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v } }
                return (data, status, headers)
            } catch let error as URLError where (error.code == .timedOut || error.code == .networkConnectionLost) && attempt < Self.maxAttempts {
                try await sleep(delay)
                delay *= 2
            } catch let error as CloudflareError {
                throw error
            } catch let error as URLError {
                throw CloudflareError.transport(String(describing: error.code))
            }
        }
        throw CloudflareError.transport("Retries exhausted")
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }

    private func decodeEnvelope<T: Decodable & Sendable>(_ data: Data, status: Int) throws -> CFEnvelope<T> {
        let env: CFEnvelope<T>
        do { env = try decoder.decode(CFEnvelope<T>.self, from: data) }
        catch {
            switch status {
            case 401: throw CloudflareError.unauthorized
            case 403: throw CloudflareError.permissionDenied(nil)
            case 200..<300: throw CloudflareError.decoding(String(describing: type(of: error)))
            default: throw CloudflareError.transport("HTTP \(status)")
            }
        }
        switch status {
        case 401: throw CloudflareError.unauthorized
        case 403: throw CloudflareError.permissionDenied(env.errors.first?.message)
        default: break
        }
        if let first = env.errors.first, !env.success || !(200..<300).contains(status) {
            throw CloudflareError.api(code: first.code, message: first.message)
        }
        if !(200..<300).contains(status) { throw CloudflareError.transport("HTTP \(status)") }
        return env
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date"))
        }
    }
}
