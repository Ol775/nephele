import Foundation

public struct KVNamespace: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct KVKey: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public let name: String
    public let expiration: Double?
    public var id: String { name }
    public init(name: String, expiration: Double? = nil) { self.name = name; self.expiration = expiration }
}

public struct KVKeyPage: Sendable, Equatable {
    public let keys: [KVKey]
    public let nextCursor: String?
}

extension CFClient {
    private func kvBase(_ account: String) -> String { "/accounts/\(account)/storage/kv/namespaces" }

    public func kvNamespaces(accountID: String) async throws -> [KVNamespace] {
        try await getAll(kvBase(accountID), perPage: 100)
    }

    public func createKVNamespace(accountID: String, title: String) async throws -> KVNamespace {
        try await send("POST", kvBase(accountID), body: JSONValue.object(["title": .string(title)]))
    }

    public func deleteKVNamespace(accountID: String, namespace: String) async throws {
        _ = try await raw("DELETE", "\(kvBase(accountID))/\(namespace)")
    }

    public func kvKeys(accountID: String, namespace: String, prefix: String? = nil, cursor: String? = nil, limit: Int = 100) async throws -> KVKeyPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let prefix, !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let env: CFEnvelope<[KVKey]> = try await get("\(kvBase(accountID))/\(namespace)/keys", query: query)
        return KVKeyPage(keys: env.result ?? [], nextCursor: env.resultInfo?.cursor)
    }

    public func kvValue(accountID: String, namespace: String, key: String) async throws -> Data {
        try await download("\(kvBase(accountID))/\(namespace)/values/\(pathSegment(key))").data
    }

    public func putKVValue(accountID: String, namespace: String, key: String, value: Data) async throws {
        _ = try await raw("PUT", "\(kvBase(accountID))/\(namespace)/values/\(pathSegment(key))", body: value, contentType: "application/octet-stream")
    }

    public func deleteKVKey(accountID: String, namespace: String, key: String) async throws {
        _ = try await raw("DELETE", "\(kvBase(accountID))/\(namespace)/values/\(pathSegment(key))")
    }
}
