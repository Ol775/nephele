import Foundation

public enum UsageRange: String, CaseIterable, Sendable { case h24 = "24h", d7 = "7d", d30 = "30d" }

public struct TrafficPoint: Sendable, Equatable {
    public let date: Date
    public let requests: Int
    public let cachedRequests: Int
    public let threats: Int
    public init(date: Date, requests: Int, cachedRequests: Int, threats: Int) {
        self.date = date; self.requests = requests; self.cachedRequests = cachedRequests; self.threats = threats
    }
}

public struct TrafficSummary: Sendable, Equatable {
    public let points: [TrafficPoint]
    public init(points: [TrafficPoint]) { self.points = points }
    public var totalRequests: Int { points.reduce(0) { $0 + $1.requests } }
    public var threats: Int { points.reduce(0) { $0 + $1.threats } }
    public var cacheHitRatio: Double {
        let total = totalRequests
        return total == 0 ? 0 : Double(points.reduce(0) { $0 + $1.cachedRequests }) / Double(total)
    }
}

public struct Meter: Sendable, Equatable, Identifiable {
    public let label: String
    public let used: Double
    public let limit: Double
    public let unit: String
    public var id: String { label }
    public init(label: String, used: Double, limit: Double, unit: String) {
        self.label = label; self.used = used; self.limit = limit; self.unit = unit
    }
    public var fraction: Double { limit <= 0 ? 0 : min(used / limit, 1) }
    public var isHot: Bool { fraction > 0.85 }
}

/// Cloudflare Free plan allowances, checked against the Workers, KV, D1 and R2 pricing docs on 2026-11-21.
public enum PlanAllowances {
    public static let free: [String: Double] = [
        "workersRequestsPerDay": 100_000,
        "kvReadsPerDay": 100_000,
        "kvWritesPerDay": 1_000,
        "d1RowsReadPerDay": 5_000_000,
        "d1RowsWrittenPerDay": 100_000,
        "r2StorageGB": 10,
    ]
}

enum AnalyticsQueries {
    static func traffic(range: UsageRange) -> String {
        if range == .h24 {
            return """
            query Traffic($zones: [String!], $start: Time!, $end: Time!) { viewer { zones(filter: { zoneTag_in: $zones }) {
              httpRequests1hGroups(limit: 1000, filter: { datetime_geq: $start, datetime_leq: $end }, orderBy: [datetime_ASC]) {
                dimensions { datetime } sum { requests cachedRequests threats } } } } }
            """
        }
        return """
        query Traffic($zones: [String!], $start: Date!, $end: Date!) { viewer { zones(filter: { zoneTag_in: $zones }) {
          httpRequests1dGroups(limit: 1000, filter: { date_geq: $start, date_leq: $end }, orderBy: [date_ASC]) {
            dimensions { date } sum { requests cachedRequests threats } } } } }
        """
    }
    static let workers = "query W($account: String!, $start: Time!, $end: Time!) { viewer { accounts(filter: { accountTag: $account }) { workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $start, datetime_leq: $end }) { sum { requests } } } } }"
    static let kv = "query K($account: String!, $day: Date!) { viewer { accounts(filter: { accountTag: $account }) { kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: $day, date_leq: $day }) { sum { requests } dimensions { actionType } } } } }"
    static let d1 = "query D($account: String!, $day: Date!) { viewer { accounts(filter: { accountTag: $account }) { d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $day, date_leq: $day }) { sum { rowsRead rowsWritten } } } } }"
    static let r2 = "query R($account: String!, $start: Time!, $end: Time!) { viewer { accounts(filter: { accountTag: $account }) { r2StorageAdaptiveGroups(limit: 10000, filter: { datetime_geq: $start, datetime_leq: $end }, orderBy: [datetime_DESC]) { max { payloadSize metadataSize } dimensions { bucketName datetime } } } } }"
}

private struct TrafficVars: Encodable, Sendable { let zones: [String]; let start: String; let end: String }
private struct AccountVars: Encodable, Sendable { let account: String; let start: String; let end: String; let day: String }

private struct TrafficData: Decodable, Sendable {
    struct Viewer: Decodable, Sendable { let zones: [ZoneSeries] }
    let viewer: Viewer
}
private struct ZoneSeries: Decodable, Sendable {
    struct Group: Decodable, Sendable {
        struct Dimensions: Decodable, Sendable { let date: String?; let datetime: String? }
        struct Sum: Decodable, Sendable { let requests: Int; let cachedRequests: Int; let threats: Int }
        let dimensions: Dimensions
        let sum: Sum
    }
    let httpRequests1hGroups: [Group]?
    let httpRequests1dGroups: [Group]?
    var groups: [Group] { (httpRequests1hGroups ?? []) + (httpRequests1dGroups ?? []) }
}

private struct AccountsData<A: Decodable & Sendable>: Decodable, Sendable {
    struct Viewer: Decodable, Sendable { let accounts: [A] }
    let viewer: Viewer
}
private struct SumRequests: Decodable, Sendable { struct S: Decodable, Sendable { let requests: Double }; let sum: S }
private struct WorkersAcct: Decodable, Sendable { let workersInvocationsAdaptive: [SumRequests] }
private struct KVAcct: Decodable, Sendable {
    struct Row: Decodable, Sendable { struct S: Decodable, Sendable { let requests: Double }; struct D: Decodable, Sendable { let actionType: String }; let sum: S; let dimensions: D }
    let kvOperationsAdaptiveGroups: [Row]
}
private struct D1Acct: Decodable, Sendable {
    struct Row: Decodable, Sendable { struct S: Decodable, Sendable { let rowsRead: Double; let rowsWritten: Double }; let sum: S }
    let d1AnalyticsAdaptiveGroups: [Row]
}
private struct R2Acct: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        struct M: Decodable, Sendable { let payloadSize: Double; let metadataSize: Double }
        struct D: Decodable, Sendable { let bucketName: String; let datetime: String }
        let max: M
        let dimensions: D
    }
    let r2StorageAdaptiveGroups: [Row]
}

private enum Day {
    static func string(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
    static func iso(_ date: Date) -> String { date.formatted(.iso8601) }
    static func parseISO(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}

extension CFClient {
    public func traffic(zoneIDs: [String], range: UsageRange, now: Date = Date()) async throws -> TrafficSummary {
        guard !zoneIDs.isEmpty else { return TrafficSummary(points: []) }
        let span: TimeInterval = switch range { case .h24: 86_400; case .d7: 7 * 86_400; case .d30: 30 * 86_400 }
        let start = now.addingTimeInterval(-span)
        // Cloudflare allows at most 10 zones in one zone-scoped query, so ask in groups of ten.
        var groups: [ZoneSeries.Group] = []
        for chunk in stride(from: 0, to: zoneIDs.count, by: 10).map({ Array(zoneIDs[$0..<min($0 + 10, zoneIDs.count)]) }) {
            let chunkVars = range == .h24
                ? TrafficVars(zones: chunk, start: Day.iso(start), end: Day.iso(now))
                : TrafficVars(zones: chunk, start: Day.string(start), end: Day.string(now))
            let data: TrafficData = try await graphQL(AnalyticsQueries.traffic(range: range), variables: chunkVars)
            groups += data.viewer.zones.flatMap(\.groups)
        }
        var merged: [Date: TrafficPoint] = [:]
        for group in groups {
            let stamp = group.dimensions.datetime.flatMap(Day.parseISO) ?? group.dimensions.date.flatMap(Day.parse)
            guard let stamp else { continue }
            let old = merged[stamp]
            merged[stamp] = TrafficPoint(date: stamp,
                requests: (old?.requests ?? 0) + group.sum.requests,
                cachedRequests: (old?.cachedRequests ?? 0) + group.sum.cachedRequests,
                threats: (old?.threats ?? 0) + group.sum.threats)
        }
        return TrafficSummary(points: merged.values.sorted { $0.date < $1.date })
    }

    /// Today's account usage against Free plan allowances. A dataset the token cannot read is skipped;
    /// the call throws only when every dataset fails.
    public func accountMeters(accountID: String, now: Date = Date()) async throws -> [Meter] {
        let day = Day.string(now)
        let dayStart = Day.parse(day) ?? now
        let vars = AccountVars(account: accountID, start: Day.iso(dayStart), end: Day.iso(now), day: day)
        let r2Vars = AccountVars(account: accountID, start: Day.iso(now.addingTimeInterval(-86_400)), end: Day.iso(now), day: day)
        let allow = PlanAllowances.free

        async let workers = loadMeters(AnalyticsQueries.workers, vars) { (d: AccountsData<WorkersAcct>) in
            let total = d.viewer.accounts.flatMap(\.workersInvocationsAdaptive).reduce(0) { $0 + $1.sum.requests }
            return [Meter(label: "Workers requests", used: total, limit: allow["workersRequestsPerDay"]!, unit: "")]
        }
        async let kv = loadMeters(AnalyticsQueries.kv, vars) { (d: AccountsData<KVAcct>) in
            let rows = d.viewer.accounts.flatMap(\.kvOperationsAdaptiveGroups)
            func total(_ type: String) -> Double { rows.filter { $0.dimensions.actionType == type }.reduce(0) { $0 + $1.sum.requests } }
            return [Meter(label: "KV reads", used: total("read"), limit: allow["kvReadsPerDay"]!, unit: ""),
                    Meter(label: "KV writes", used: total("write"), limit: allow["kvWritesPerDay"]!, unit: "")]
        }
        async let d1 = loadMeters(AnalyticsQueries.d1, vars) { (d: AccountsData<D1Acct>) in
            let rows = d.viewer.accounts.flatMap(\.d1AnalyticsAdaptiveGroups)
            return [Meter(label: "D1 rows read", used: rows.reduce(0) { $0 + $1.sum.rowsRead }, limit: allow["d1RowsReadPerDay"]!, unit: ""),
                    Meter(label: "D1 rows written", used: rows.reduce(0) { $0 + $1.sum.rowsWritten }, limit: allow["d1RowsWrittenPerDay"]!, unit: "")]
        }
        async let r2 = loadMeters(AnalyticsQueries.r2, r2Vars) { (d: AccountsData<R2Acct>) in
            var latest: [String: (Date, Double)] = [:]
            for row in d.viewer.accounts.flatMap(\.r2StorageAdaptiveGroups) {
                guard let at = Day.parseISO(row.dimensions.datetime) else { continue }
                let size = row.max.payloadSize + row.max.metadataSize
                if latest[row.dimensions.bucketName].map({ at > $0.0 }) ?? true { latest[row.dimensions.bucketName] = (at, size) }
            }
            let gb = latest.values.reduce(0) { $0 + $1.1 } / 1_000_000_000
            return [Meter(label: "R2 storage", used: gb, limit: allow["r2StorageGB"]!, unit: "GB")]
        }

        var meters: [Meter] = []
        var failures: [CloudflareError] = []
        for result in [await workers, await kv, await d1, await r2] {
            switch result {
            case .success(let m): meters += m
            case .failure(let e): failures.append(e)
            }
        }
        if meters.isEmpty, let first = failures.first { throw first }
        return meters
    }

    private func loadMeters<D: Decodable & Sendable>(_ query: String, _ vars: AccountVars, _ build: (D) -> [Meter]) async -> Result<[Meter], CloudflareError> {
        do {
            let data: D = try await graphQL(query, variables: vars)
            return .success(build(data))
        } catch let error as CloudflareError {
            return .failure(error)
        } catch {
            return .failure(.transport("unknown"))
        }
    }
}
