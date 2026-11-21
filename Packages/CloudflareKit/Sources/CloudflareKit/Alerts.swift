import Foundation

public enum AlertSeverity: String, Codable, Sendable { case info, warning, critical }

public struct AlertPolicy: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let alertType: String
    public let enabled: Bool
}

public struct AlertEvent: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let alertType: String
    public let sent: Date
    public let severity: AlertSeverity

    public init(id: String, name: String, alertType: String, sent: Date, severity: AlertSeverity) {
        self.id = id; self.name = name; self.alertType = alertType; self.sent = sent; self.severity = severity
    }

    private enum CodingKeys: String, CodingKey { case id, name, alertType, sent }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        alertType = try c.decode(String.self, forKey: .alertType)
        sent = try c.decode(Date.self, forKey: .sent)
        severity = Self.severity(forAlertType: alertType)
    }

    /// Cloudflare does not send a severity; derive one from the alert type.
    static func severity(forAlertType type: String) -> AlertSeverity {
        let t = type.lowercased()
        if t.contains("origin_error") || t.contains("attack") || t.contains("5xx") { return .critical }
        if t.contains("expir") || t.contains("ssl") || t.contains("certificate") || t.contains("edge_error") { return .warning }
        return .info
    }
}

extension CFClient {
    public func alertPolicies(accountID: String) async throws -> [AlertPolicy] {
        try await getAll("/accounts/\(accountID)/alerting/v3/policies", perPage: 100)
    }
    public func alertHistory(accountID: String) async throws -> [AlertEvent] {
        try await getAll("/accounts/\(accountID)/alerting/v3/history", perPage: 100)
    }
}

/// Remembers which alert events were already seen so each notifies once.
public struct AlertDeduper: Codable, Sendable, Equatable {
    public let maxRemembered: Int
    public private(set) var isPrimed = false
    public var rememberedCount: Int { seen.count }
    private var seen: [String] = []

    public init(maxRemembered: Int = 500) { self.maxRemembered = maxRemembered }

    public mutating func newEvents(_ events: [AlertEvent]) -> [AlertEvent] {
        var known = Set(seen)
        var fresh: [AlertEvent] = []
        for event in events where known.insert(event.id).inserted { fresh.append(event) }
        seen += fresh.map(\.id)
        // Never forget events from the batch just seen, or a history longer than the limit re-notifies forever.
        let limit = max(maxRemembered, events.count)
        if seen.count > limit { seen.removeFirst(seen.count - limit) }
        return fresh
    }

    /// Marks existing history as seen without reporting it (first run, so no notification flood).
    public mutating func prime(_ events: [AlertEvent]) {
        _ = newEvents(events)
        isPrimed = true
    }
}
