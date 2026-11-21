import Foundation

public struct WorkerScript: Codable, Sendable, Identifiable, Hashable {
    /// The Worker's name.
    public let id: String
    public let createdOn: Date?
    public let modifiedOn: Date?
    public let compatibilityDate: String?
    public let handlers: [String]?

    public init(id: String, createdOn: Date? = nil, modifiedOn: Date? = nil, compatibilityDate: String? = nil, handlers: [String]? = nil) {
        self.id = id; self.createdOn = createdOn; self.modifiedOn = modifiedOn
        self.compatibilityDate = compatibilityDate; self.handlers = handlers
    }
}

public struct DeploymentVersion: Codable, Sendable, Equatable {
    public let versionId: String
    public let percentage: Double
    public init(versionId: String, percentage: Double) { self.versionId = versionId; self.percentage = percentage }
}

public struct WorkerDeployment: Sendable, Identifiable, Equatable, Decodable {
    public let id: String
    public let createdOn: Date
    public let message: String?
    public let versions: [DeploymentVersion]

    public init(id: String, createdOn: Date, message: String? = nil, versions: [DeploymentVersion]) {
        self.id = id; self.createdOn = createdOn; self.message = message; self.versions = versions
    }

    private enum CodingKeys: String, CodingKey { case id, createdOn, annotations, versions }
    private struct Annotations: Decodable {
        let message: String?
        private struct Key: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            message = try c.decodeIfPresent(String.self, forKey: Key(stringValue: "workers/message")!)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdOn = try c.decode(Date.self, forKey: .createdOn)
        message = try c.decodeIfPresent(Annotations.self, forKey: .annotations)?.message
        versions = try c.decodeIfPresent([DeploymentVersion].self, forKey: .versions) ?? []
    }
}

private struct DeploymentList: Decodable, Sendable { let deployments: [WorkerDeployment] }

extension CFClient {
    public func workers(accountID: String) async throws -> [WorkerScript] {
        let env: CFEnvelope<[WorkerScript]> = try await get("/accounts/\(accountID)/workers/scripts")
        return env.result ?? []
    }

    /// Newest first.
    public func deployments(accountID: String, script: String) async throws -> [WorkerDeployment] {
        let env: CFEnvelope<DeploymentList> = try await get("/accounts/\(accountID)/workers/scripts/\(script)/deployments")
        return (env.result?.deployments ?? []).sorted { $0.createdOn > $1.createdOn }
    }
}
