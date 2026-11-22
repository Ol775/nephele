import Foundation

public struct PagesStage: Codable, Sendable, Equatable, Hashable {
    public let name: String?
    /// success, failure, active, idle, canceled or skipped.
    public let status: String?
}

public struct PagesTrigger: Codable, Sendable, Equatable, Hashable {
    public let branch: String?
    public let commitMessage: String?
    public let commitHash: String?
}

public struct PagesDeployment: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public let id: String
    public let shortId: String?
    /// production or preview.
    public let environment: String?
    public let url: String?
    public let createdOn: String?
    public let latestStage: PagesStage?
    public let trigger: PagesTrigger?

    private enum CodingKeys: String, CodingKey { case id, shortId, environment, url, createdOn, latestStage, deploymentTrigger }
    private struct Trigger: Decodable, Sendable { let metadata: PagesTrigger? }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortId = try c.decodeIfPresent(String.self, forKey: .shortId)
        environment = try c.decodeIfPresent(String.self, forKey: .environment)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        createdOn = try c.decodeIfPresent(String.self, forKey: .createdOn)
        latestStage = try c.decodeIfPresent(PagesStage.self, forKey: .latestStage)
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .deploymentTrigger)?.metadata
    }
    public init(id: String, environment: String? = nil, status: String? = nil) {
        self.id = id; shortId = nil; self.environment = environment; url = nil; createdOn = nil
        latestStage = PagesStage(name: nil, status: status); trigger = nil
    }
}

public struct PagesProject: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let name: String
    public let subdomain: String?
    public let domains: [String]?
    public let productionBranch: String?
    public let createdOn: String?
    public let latestDeployment: PagesDeployment?
    public var id: String { name }
    public init(name: String) { self.name = name; subdomain = nil; domains = nil; productionBranch = nil; createdOn = nil; latestDeployment = nil }

    private enum CodingKeys: String, CodingKey { case name, subdomain, domains, productionBranch, createdOn, latestDeployment }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        subdomain = try c.decodeIfPresent(String.self, forKey: .subdomain)
        domains = try c.decodeIfPresent([String].self, forKey: .domains)
        productionBranch = try c.decodeIfPresent(String.self, forKey: .productionBranch)
        createdOn = try c.decodeIfPresent(String.self, forKey: .createdOn)
        latestDeployment = try? c.decodeIfPresent(PagesDeployment.self, forKey: .latestDeployment)
    }
    public func encode(to encoder: any Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(name, forKey: .name) }
}

extension CFClient {
    private func pagesBase(_ account: String) -> String { "/accounts/\(account)/pages/projects" }
    private func depBase(_ account: String, _ project: String) -> String { "\(pagesBase(account))/\(pathSegment(project))/deployments" }

    public func pagesProjects(accountID: String) async throws -> [PagesProject] {
        try await getAll(pagesBase(accountID), perPage: 10)
    }

    public func pagesDeployments(accountID: String, project: String) async throws -> [PagesDeployment] {
        let env: CFEnvelope<[PagesDeployment]> = try await get(depBase(accountID, project), query: [URLQueryItem(name: "per_page", value: "25")])
        return env.result ?? []
    }

    public func retryPagesDeployment(accountID: String, project: String, id: String) async throws {
        _ = try await raw("POST", "\(depBase(accountID, project))/\(pathSegment(id))/retry")
    }

    /// Makes an earlier successful production deployment the live one again.
    public func rollbackPagesDeployment(accountID: String, project: String, id: String) async throws {
        _ = try await raw("POST", "\(depBase(accountID, project))/\(pathSegment(id))/rollback")
    }

    public func deletePagesDeployment(accountID: String, project: String, id: String) async throws {
        _ = try await raw("DELETE", "\(depBase(accountID, project))/\(pathSegment(id))")
    }

    public func deletePagesProject(accountID: String, name: String) async throws {
        _ = try await raw("DELETE", "\(pagesBase(accountID))/\(pathSegment(name))")
    }
}
