import Foundation

public struct D1Database: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let uuid: String
    public let name: String
    public let createdAt: String?
    public var id: String { uuid }
    public init(uuid: String, name: String, createdAt: String? = nil) { self.uuid = uuid; self.name = name; self.createdAt = createdAt }
}

public struct D1Result: Sendable, Equatable {
    public let columns: [String]
    public let rows: [[String]]
    public let rowsRead: Int
    public let rowsWritten: Int
    public let duration: Double
    public init(columns: [String], rows: [[String]], rowsRead: Int = 0, rowsWritten: Int = 0, duration: Double = 0) {
        self.columns = columns; self.rows = rows; self.rowsRead = rowsRead; self.rowsWritten = rowsWritten; self.duration = duration
    }
}

public enum D1SQL {
    private static let writeWords: Set<String> = ["insert", "update", "delete", "replace", "drop", "alter", "create", "attach", "detach", "vacuum", "reindex", "truncate"]

    /// True only when every statement is a plain read: SELECT, WITH, EXPLAIN or a PRAGMA that sets nothing,
    /// with no write keyword anywhere in it. Anything doubtful counts as a write, so it asks first.
    public static func isReadOnly(_ sql: String) -> Bool {
        let statements = stripComments(sql).split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !statements.isEmpty else { return false }
        return statements.allSatisfy { statement in
            let words = statement.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
            guard let first = words.first, ["select", "with", "explain", "pragma"].contains(first) else { return false }
            if first == "pragma" && statement.contains("=") { return false }
            return !words.contains { writeWords.contains($0) }
        }
    }

    private static func stripComments(_ sql: String) -> String {
        var out = "", i = sql.startIndex
        while i < sql.endIndex {
            if sql[i...].hasPrefix("--") {
                while i < sql.endIndex, sql[i] != "\n" { i = sql.index(after: i) }
            } else if sql[i...].hasPrefix("/*") {
                if let end = sql.range(of: "*/", range: i..<sql.endIndex) { i = end.upperBound } else { i = sql.endIndex }
                out += " "
            } else { out.append(sql[i]); i = sql.index(after: i) }
        }
        return out
    }
}

private struct RawQuery: Decodable {
    struct Item: Decodable {
        struct Table: Decodable { let columns: [String]; let rows: [[JSONValue]] }
        struct Meta: Decodable { let rows_read: Double?; let rows_written: Double?; let duration: Double? }
        let results: Table?
        let meta: Meta?
    }
    let result: [Item]
}

private func render(_ v: JSONValue) -> String {
    switch v {
    case .null: "NULL"
    case .bool(let b): b ? "true" : "false"
    case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
    case .string(let s): s
    default: (try? JSONEncoder.sorted.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }
}

extension CFClient {
    private func d1Base(_ account: String) -> String { "/accounts/\(account)/d1/database" }

    public func d1Databases(accountID: String) async throws -> [D1Database] {
        try await getAll(d1Base(accountID), perPage: 100)
    }

    public func createD1Database(accountID: String, name: String) async throws -> D1Database {
        guard name.wholeMatch(of: /[a-zA-Z0-9][a-zA-Z0-9_-]*/) != nil else { throw WorkerValidationError.invalidName }
        return try await send("POST", d1Base(accountID), body: JSONValue.object(["name": .string(name)]))
    }

    public func deleteD1Database(accountID: String, database: String) async throws {
        _ = try await raw("DELETE", "\(d1Base(accountID))/\(database)")
    }

    /// Runs SQL on the raw endpoint, which returns ordered columns and row arrays (one result per statement).
    public func queryD1(accountID: String, database: String, sql: String) async throws -> [D1Result] {
        let body = try JSONEncoder().encode(JSONValue.object(["sql": .string(sql)]))
        let data = try await raw("POST", "\(d1Base(accountID))/\(database)/raw", body: body)
        do {
            return try JSONDecoder().decode(RawQuery.self, from: data).result.map { item in
                D1Result(columns: item.results?.columns ?? [], rows: (item.results?.rows ?? []).map { $0.map(render) },
                         rowsRead: Int(item.meta?.rows_read ?? 0), rowsWritten: Int(item.meta?.rows_written ?? 0), duration: item.meta?.duration ?? 0)
            }
        } catch { throw CloudflareError.decoding("d1 query") }
    }
}
