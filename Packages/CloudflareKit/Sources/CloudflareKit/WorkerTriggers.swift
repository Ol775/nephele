import Foundation

public struct WorkerRoute: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let pattern: String
    public let script: String?
    public init(id: String, pattern: String, script: String? = nil) { self.id = id; self.pattern = pattern; self.script = script }
}

public struct WorkerDomain: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let hostname: String
    public let service: String
    public let zoneId: String?
    public let zoneName: String?
    public init(id: String, hostname: String, service: String, zoneId: String? = nil, zoneName: String? = nil) {
        self.id = id; self.hostname = hostname; self.service = service; self.zoneId = zoneId; self.zoneName = zoneName
    }
}

/// A route pattern must target the zone: its host is the zone or a subdomain, optionally with a leading `*.`.
public func validRoutePattern(_ pattern: String, zone: String) -> Bool {
    guard !pattern.isEmpty, pattern.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
    var host = String(pattern.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").lowercased()
    if host.hasPrefix("*.") { host.removeFirst(2) }
    let zone = zone.lowercased()
    guard host.wholeMatch(of: /[a-z0-9.-]+/) != nil else { return false }
    return host == zone || host.hasSuffix("." + zone)
}

/// Five whitespace-separated fields. Each is `*`, numbers, ranges, steps, lists, or day and month names.
public func validCron(_ cron: String) -> Bool {
    let fields = cron.split(whereSeparator: \.isWhitespace)
    guard fields.count == 5 else { return false }
    let names: Set<String> = ["sun", "mon", "tue", "wed", "thu", "fri", "sat", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    return fields.allSatisfy { field in
        field.split(whereSeparator: { ",-/".contains($0) }).allSatisfy { token in
            token == "*" || token.allSatisfy(\.isNumber) || names.contains(token.lowercased())
        } && !field.isEmpty
    }
}

private struct Schedules: Decodable, Sendable {
    struct Item: Decodable, Sendable { let cron: String }
    let schedules: [Item]
}

extension CFClient {
    public func workerRoutes(zoneID: String) async throws -> [WorkerRoute] {
        let env: CFEnvelope<[WorkerRoute]> = try await get("/zones/\(zoneID)/workers/routes")
        return env.result ?? []
    }

    public func createWorkerRoute(zoneID: String, pattern: String, script: String) async throws {
        let body = try JSONEncoder().encode(JSONValue.object(["pattern": .string(pattern), "script": .string(script)]))
        _ = try await raw("POST", "/zones/\(zoneID)/workers/routes", body: body)
    }

    public func deleteWorkerRoute(zoneID: String, id: String) async throws {
        _ = try await raw("DELETE", "/zones/\(zoneID)/workers/routes/\(id)")
    }

    public func workerDomains(accountID: String, service: String? = nil) async throws -> [WorkerDomain] {
        let query = service.map { [URLQueryItem(name: "service", value: $0)] } ?? []
        let env: CFEnvelope<[WorkerDomain]> = try await get("/accounts/\(accountID)/workers/domains", query: query)
        return env.result ?? []
    }

    public func attachWorkerDomain(accountID: String, hostname: String, script: String, zoneID: String) async throws {
        let body = try JSONEncoder().encode(JSONValue.object([
            "hostname": .string(hostname), "service": .string(script), "zone_id": .string(zoneID), "environment": .string("production"),
        ]))
        _ = try await raw("PUT", "/accounts/\(accountID)/workers/domains", body: body)
    }

    public func detachWorkerDomain(accountID: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/workers/domains/\(id)")
    }

    public func workerSchedules(accountID: String, script: String) async throws -> [String] {
        let env: CFEnvelope<Schedules> = try await get("/accounts/\(accountID)/workers/scripts/\(script)/schedules")
        return (env.result?.schedules ?? []).map(\.cron)
    }

    public func setWorkerSchedules(accountID: String, script: String, _ crons: [String]) async throws {
        let body = try JSONEncoder().encode(JSONValue.array(crons.map { .object(["cron": .string($0)]) }))
        _ = try await raw("PUT", "/accounts/\(accountID)/workers/scripts/\(script)/schedules", body: body)
    }
}
