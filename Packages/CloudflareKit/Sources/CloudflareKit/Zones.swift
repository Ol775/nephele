import Foundation

public struct Zone: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let status: String
    public let paused: Bool
    public let planName: String
    public let nameServers: [String]
    public let accountID: String

    public init(id: String, name: String, status: String, paused: Bool = false, planName: String, nameServers: [String] = [], accountID: String) {
        self.id = id; self.name = name; self.status = status; self.paused = paused
        self.planName = planName; self.nameServers = nameServers; self.accountID = accountID
    }

    private enum CodingKeys: String, CodingKey { case id, name, status, paused, nameServers, plan, account }
    private struct Plan: Decodable { let name: String }
    private struct Account: Decodable { let id: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        status = try c.decode(String.self, forKey: .status)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        nameServers = try c.decodeIfPresent([String].self, forKey: .nameServers) ?? []
        planName = try c.decodeIfPresent(Plan.self, forKey: .plan)?.name ?? "Unknown"
        accountID = try c.decode(Account.self, forKey: .account).id
    }
}

extension CFClient {
    public func zones() async throws -> [Zone] {
        try await getAll("/zones", perPage: 50)
    }
}
