import Foundation

public enum WorkerValidationError: Error, Equatable, LocalizedError {
    case messageTooLong, messageRequired
    public var errorDescription: String? {
        switch self {
        case .messageTooLong: "Keep the message under 1,000 bytes."
        case .messageRequired: "Add a short message describing this change."
        }
    }
}

public struct WorkerVersion: Sendable, Identifiable, Equatable, Decodable {
    public let id: String
    public let number: Int?
    public let createdOn: Date?
    public let message: String?
    public let authorEmail: String?

    public init(id: String, number: Int? = nil, createdOn: Date? = nil, message: String? = nil, authorEmail: String? = nil) {
        self.id = id; self.number = number; self.createdOn = createdOn; self.message = message; self.authorEmail = authorEmail
    }

    private enum CodingKeys: String, CodingKey { case id, number, metadata, annotations }
    private struct Metadata: Decodable { let createdOn: Date?; let authorEmail: String? }
    private struct Annotations: Decodable {
        let message: String?
        private struct Key: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        init(from decoder: any Decoder) throws {
            message = try decoder.container(keyedBy: Key.self).decodeIfPresent(String.self, forKey: Key(stringValue: "workers/message")!)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        let meta = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
        createdOn = meta?.createdOn
        authorEmail = meta?.authorEmail
        message = try c.decodeIfPresent(Annotations.self, forKey: .annotations)?.message
    }
}

private struct VersionList: Decodable, Sendable { let items: [WorkerVersion] }

extension CFClient {
    /// Newest first (up to 50).
    public func workerVersions(accountID: String, script: String) async throws -> [WorkerVersion] {
        let env: CFEnvelope<VersionList> = try await get("/accounts/\(accountID)/workers/scripts/\(script)/versions", query: [URLQueryItem(name: "per_page", value: "50")])
        return (env.result?.items ?? []).sorted { ($0.number ?? 0, $0.createdOn ?? .distantPast) > ($1.number ?? 0, $1.createdOn ?? .distantPast) }
    }

    /// Makes one version take 100% of traffic. Rolling back is deploying an older version.
    public func deployVersion(accountID: String, script: String, versionID: String, message: String) async throws -> WorkerDeployment {
        guard message.utf8.count <= 1000 else { throw WorkerValidationError.messageTooLong }
        let body = JSONValue.object([
            "strategy": .string("percentage"),
            "versions": .array([.object(["version_id": .string(versionID), "percentage": .number(100)])]),
            "annotations": .object(["workers/message": .string(message)]),
        ])
        return try await send("POST", "/accounts/\(accountID)/workers/scripts/\(script)/deployments", body: body)
    }
}
