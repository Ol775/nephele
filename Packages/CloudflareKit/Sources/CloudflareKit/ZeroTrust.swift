import Foundation

public struct TunnelConnection: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String?
    public let coloName: String?
    public let originIp: String?
    public let openedAt: String?
    public var stableID: String { id ?? "\(coloName ?? "")-\(originIp ?? "")-\(openedAt ?? "")" }
}

public struct Tunnel: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// healthy, degraded, down or inactive.
    public let status: String?
    public let createdAt: String?
    public let connections: [TunnelConnection]?
    public init(id: String, name: String, status: String? = nil, createdAt: String? = nil, connections: [TunnelConnection]? = nil) {
        self.id = id; self.name = name; self.status = status; self.createdAt = createdAt; self.connections = connections
    }
}

public struct AccessPolicyRef: Codable, Sendable, Equatable, Hashable { public let id: String? }

public struct AccessApp: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let domain: String?
    public let type: String?
    public let sessionDuration: String?
    public let policies: [AccessPolicyRef]?
    public init(id: String, name: String, domain: String? = nil, type: String? = nil, sessionDuration: String? = nil, policies: [AccessPolicyRef]? = nil) {
        self.id = id; self.name = name; self.domain = domain; self.type = type; self.sessionDuration = sessionDuration; self.policies = policies
    }
}

public struct ServiceToken: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let clientID: String?
    public let createdAt: String?
    public let expiresAt: String?
    public let duration: String?
    public init(id: String, name: String, clientID: String? = nil, createdAt: String? = nil, expiresAt: String? = nil, duration: String? = nil) {
        self.id = id; self.name = name; self.clientID = clientID; self.createdAt = createdAt; self.expiresAt = expiresAt; self.duration = duration
    }
    private enum CodingKeys: String, CodingKey { case id, name, clientID = "clientId", createdAt, expiresAt, duration }
}

/// Cloudflare returns the secret once, on creation. It is deliberately not part of `ServiceToken`.
public struct CreatedServiceToken: Sendable, Equatable {
    public let token: ServiceToken
    public let clientSecret: String
}

private struct CreatedTokenWire: Decodable, Sendable { let clientSecret: String? }

/// 1 to 100 characters, not blank.
public func validTunnelName(_ name: String) -> Bool {
    let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !t.isEmpty && t.count <= 100
}

extension CFClient {
    public func tunnels(accountID: String) async throws -> [Tunnel] {
        try await getAll("/accounts/\(accountID)/cfd_tunnel", query: [URLQueryItem(name: "is_deleted", value: "false")], perPage: 100)
    }

    public func createTunnel(accountID: String, name: String) async throws -> Tunnel {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validTunnelName(name) else { throw WorkerValidationError.invalidName }
        return try await send("POST", "/accounts/\(accountID)/cfd_tunnel", body: JSONValue.object(["name": .string(name), "config_src": .string("cloudflare")]))
    }

    public func deleteTunnel(accountID: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/cfd_tunnel/\(pathSegment(id))")
    }

    public func accessApps(accountID: String) async throws -> [AccessApp] {
        try await getAll("/accounts/\(accountID)/access/apps", perPage: 100)
    }

    public func deleteAccessApp(accountID: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/access/apps/\(pathSegment(id))")
    }

    public func serviceTokens(accountID: String) async throws -> [ServiceToken] {
        try await getAll("/accounts/\(accountID)/access/service_tokens", perPage: 100)
    }

    public func createServiceToken(accountID: String, name: String, duration: String) async throws -> CreatedServiceToken {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validTunnelName(name) else { throw WorkerValidationError.invalidName }
        let body = try JSONEncoder().encode(["name": name, "duration": duration])
        let data = try await raw("POST", "/accounts/\(accountID)/access/service_tokens", body: body)
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        guard let token = try? d.decode(CFEnvelope<ServiceToken>.self, from: data).result,
              let secret = try? d.decode(CFEnvelope<CreatedTokenWire>.self, from: data).result?.clientSecret, !secret.isEmpty
        else { throw CloudflareError.decoding("Missing service token") }
        return CreatedServiceToken(token: token, clientSecret: secret)
    }

    public func deleteServiceToken(accountID: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/access/service_tokens/\(pathSegment(id))")
    }
}
