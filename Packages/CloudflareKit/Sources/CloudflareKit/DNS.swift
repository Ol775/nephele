import Foundation
import Network

public struct DNSRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let type: String
    public let name: String
    public let content: String
    public let proxied: Bool?
    public let ttl: Int
    public let priority: Int?

    public init(id: String, type: String, name: String, content: String, proxied: Bool? = nil, ttl: Int = 1, priority: Int? = nil) {
        self.id = id; self.type = type; self.name = name; self.content = content
        self.proxied = proxied; self.ttl = ttl; self.priority = priority
    }
}

public struct DNSRecordDraft: Sendable, Equatable, Encodable {
    public var type: String
    public var name: String
    public var content: String
    public var proxied: Bool
    public var ttl: Int
    public var priority: Int?

    public init(type: String, name: String, content: String, proxied: Bool, ttl: Int = 1, priority: Int? = nil) {
        self.type = type; self.name = name; self.content = content
        self.proxied = proxied; self.ttl = ttl; self.priority = priority
    }
}

public enum DNSValidationError: Error, Equatable, LocalizedError {
    case emptyName, emptyContent, notIPv4, notIPv6, notHostname, missingPriority

    public var errorDescription: String? {
        switch self {
        case .emptyName, .emptyContent: "Enter a name and content for the record."
        case .notIPv4: "An A record needs an IPv4 address, such as 192.0.2.10."
        case .notIPv6: "An AAAA record needs an IPv6 address, such as 2001:db8::1."
        case .notHostname: "That needs a hostname, such as app.example.dev."
        case .missingPriority: "An MX record needs a priority, such as 10."
        }
    }
}

extension DNSRecordDraft {
    private static let proxiable: Set<String> = ["A", "AAAA", "CNAME"]
    private static func isHostname(_ s: String) -> Bool {
        s.lowercased().wholeMatch(of: /([a-z0-9_-]+\.)*[a-z0-9_-]+\.?/) != nil
    }

    /// Normalises and checks a draft against its zone. Pure: no network.
    public func validated(zone: String) throws -> DNSRecordDraft {
        var out = self
        out.type = type.uppercased()
        let rawName = name.trimmingCharacters(in: .whitespaces).lowercased()
        let content = content.trimmingCharacters(in: .whitespaces)
        guard !rawName.isEmpty else { throw DNSValidationError.emptyName }
        guard !content.isEmpty else { throw DNSValidationError.emptyContent }
        let zone = zone.lowercased()
        var fullName = rawName.hasSuffix(".") ? String(rawName.dropLast()) : rawName
        if fullName == "@" { fullName = zone }
        else if fullName != zone && !fullName.hasSuffix("." + zone) { fullName += "." + zone }
        out.name = fullName
        out.content = content
        switch out.type {
        case "A": guard IPv4Address(content) != nil else { throw DNSValidationError.notIPv4 }
        case "AAAA": guard IPv6Address(content) != nil else { throw DNSValidationError.notIPv6 }
        case "CNAME": guard Self.isHostname(content) else { throw DNSValidationError.notHostname }
        case "MX":
            guard Self.isHostname(content) else { throw DNSValidationError.notHostname }
            guard priority != nil else { throw DNSValidationError.missingPriority }
        default: break
        }
        out.proxied = proxied && Self.proxiable.contains(out.type)
        if out.proxied { out.ttl = 1 }  // Cloudflare only allows automatic TTL on proxied records
        return out
    }
}

private struct Deleted: Decodable, Sendable { let id: String }

extension CFClient {
    public func dnsRecords(zoneID: String) async throws -> [DNSRecord] {
        try await getAll("/zones/\(zoneID)/dns_records", perPage: 100)
    }
    public func createDNSRecord(zoneID: String, _ draft: DNSRecordDraft) async throws -> DNSRecord {
        try await send("POST", "/zones/\(zoneID)/dns_records", body: draft)
    }
    public func updateDNSRecord(zoneID: String, id: String, _ draft: DNSRecordDraft) async throws -> DNSRecord {
        try await send("PATCH", "/zones/\(zoneID)/dns_records/\(id)", body: draft)
    }
    public func deleteDNSRecord(zoneID: String, id: String) async throws {
        let _: Deleted = try await send("DELETE", "/zones/\(zoneID)/dns_records/\(id)")
    }
}
