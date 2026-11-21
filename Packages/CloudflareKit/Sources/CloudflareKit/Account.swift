import Foundation

public struct TokenStatus: Decodable, Sendable, Equatable {
    public let id: String
    public let status: String
    public init(id: String, status: String) { self.id = id; self.status = status }
}

public struct CFAccount: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct PermissionStatus: Sendable, Equatable, Identifiable {
    public let name: String
    public let level: String
    public let granted: Bool
    public var id: String { name }
    public init(name: String, level: String, granted: Bool) { self.name = name; self.level = level; self.granted = granted }
}

private struct Ignored: Decodable, Sendable {
    init(from decoder: any Decoder) throws {}
}

extension CFClient {
    /// User tokens verify at /user/tokens/verify; account-owned (cfat_) tokens verify under their account.
    public func verifyToken(accountID: String? = nil) async throws -> TokenStatus {
        let env: CFEnvelope<TokenStatus> = try await get(accountID.map { "/accounts/\($0)/tokens/verify" } ?? "/user/tokens/verify")
        guard let status = env.result else { throw CloudflareError.decoding("Missing result") }
        return status
    }

    public func accounts() async throws -> [CFAccount] {
        try await getAll("/accounts", perPage: 50)
    }

    /// Probes one cheap read endpoint per permission. Only edit rights cannot be checked without writing.
    public func probePermissions(accountID: String, zoneID: String?) async -> [PermissionStatus] {
        var probes: [(String, String)] = [("Zone", "/zones")]
        if let zoneID { probes.append(("DNS", "/zones/\(zoneID)/dns_records")) }
        probes += [
            ("Workers Scripts", "/accounts/\(accountID)/workers/scripts"),
            ("Workers KV Storage", "/accounts/\(accountID)/storage/kv/namespaces"),
            ("D1", "/accounts/\(accountID)/d1/database"),
            ("Workers R2 Storage", "/accounts/\(accountID)/r2/buckets"),
            ("Access: Apps and Policies", "/accounts/\(accountID)/access/apps"),
            ("Cloudflare Tunnel", "/accounts/\(accountID)/cfd_tunnel"),
            ("Notifications", "/accounts/\(accountID)/alerting/v3/policies"),
        ]
        var granted = [Bool](repeating: false, count: probes.count)
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, probe) in probes.enumerated() {
                group.addTask {
                    do {
                        let _: CFEnvelope<Ignored> = try await self.get(probe.1, query: [URLQueryItem(name: "per_page", value: "1")])
                        return (index, true)
                    } catch { return (index, false) }
                }
            }
            for await (index, ok) in group { granted[index] = ok }
        }
        return probes.enumerated().map { PermissionStatus(name: $0.element.0, level: "Read (edit not checked)", granted: granted[$0.offset]) }
    }
}
