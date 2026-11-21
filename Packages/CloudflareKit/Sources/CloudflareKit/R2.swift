import Foundation

public struct R2Bucket: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let name: String
    public let creationDate: String?
    public let location: String?
    public var id: String { name }
    public init(name: String, creationDate: String? = nil, location: String? = nil) { self.name = name; self.creationDate = creationDate; self.location = location }
}

public struct R2Object: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public let key: String
    public let size: Int?
    public let lastModified: String?
    public let storageClass: String?
    public var id: String { key }
    public init(key: String, size: Int? = nil, lastModified: String? = nil, storageClass: String? = nil) {
        self.key = key; self.size = size; self.lastModified = lastModified; self.storageClass = storageClass
    }
}

public struct R2ObjectPage: Sendable, Equatable {
    public let objects: [R2Object]
    public let nextCursor: String?
}

/// 3 to 63 characters: lowercase letters, digits and hyphens, not starting or ending with a hyphen.
public func validBucketName(_ name: String) -> Bool {
    (3...63).contains(name.count) && name.wholeMatch(of: /[a-z0-9]([a-z0-9-]*[a-z0-9])?/) != nil
}

private struct BucketList: Decodable, Sendable { let buckets: [R2Bucket] }

extension CFClient {
    private func r2Base(_ account: String) -> String { "/accounts/\(account)/r2/buckets" }

    public func r2Buckets(accountID: String) async throws -> [R2Bucket] {
        let env: CFEnvelope<BucketList> = try await get(r2Base(accountID))
        return env.result?.buckets ?? []
    }

    public func createR2Bucket(accountID: String, name: String) async throws -> R2Bucket {
        guard validBucketName(name) else { throw WorkerValidationError.invalidName }
        return try await send("POST", r2Base(accountID), body: JSONValue.object(["name": .string(name)]))
    }

    public func deleteR2Bucket(accountID: String, bucket: String) async throws {
        _ = try await raw("DELETE", "\(r2Base(accountID))/\(pathSegment(bucket))")
    }

    public func r2Objects(accountID: String, bucket: String, prefix: String? = nil, cursor: String? = nil, perPage: Int = 100) async throws -> R2ObjectPage {
        var query = [URLQueryItem(name: "per_page", value: String(perPage))]
        if let prefix, !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let env: CFEnvelope<[R2Object]> = try await get("\(r2Base(accountID))/\(pathSegment(bucket))/objects", query: query)
        return R2ObjectPage(objects: env.result ?? [], nextCursor: env.resultInfo?.cursor)
    }

    public func deleteR2Object(accountID: String, bucket: String, key: String) async throws {
        _ = try await raw("DELETE", "\(r2Base(accountID))/\(pathSegment(bucket))/objects/\(pathSegment(key))")
    }
}
