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
    /// PRAGMAs that only read, with their usual argument form.
    private static let readPragmas: Set<String> = ["table_info", "table_xinfo", "table_list", "index_list", "index_info", "index_xinfo", "foreign_key_list", "database_list", "collation_list"]

    /// `"name"` with any quote doubled, for building SQL around a table name.
    public static func quoteIdentifier(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    /// True only when every statement is a plain read: SELECT, WITH, EXPLAIN or a read-only PRAGMA, with no write
    /// keyword in its code (text inside quotes and comments is skipped by a real scanner, not guessed at).
    /// Anything doubtful, including an unclosed quote or comment, counts as a write so it asks first.
    public static func isReadOnly(_ sql: String) -> Bool {
        guard let statements = split(sql), !statements.isEmpty else { return false }
        return statements.allSatisfy { code in
            let words = code.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
            guard let first = words.first, ["select", "with", "explain", "pragma"].contains(first) else { return false }
            if first == "pragma" {
                guard words.count >= 2, readPragmas.contains(words[1]), !code.contains("=") else { return false }
            }
            return !words.contains { writeWords.contains($0) }
        }
    }

    /// Splits on `;` outside quotes and drops comments. Quoted text becomes `''` so only code remains.
    /// Returns nil when a quote, bracket or block comment is never closed.
    static func split(_ sql: String) -> [String]? {
        // Scalars, not Characters: SQLite reads code points, and "\r\n" or a quote plus a combining mark
        // would otherwise be one Character that matches neither "\n" nor the quote.
        var statements: [String] = [], current = String.UnicodeScalarView()
        let chars = Array(sql.unicodeScalars)
        var i = 0
        func at(_ k: Int) -> Unicode.Scalar? { k < chars.count ? chars[k] : nil }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "'", "\"", "`":
                var j = i + 1, closed = false
                while j < chars.count {
                    if chars[j] == c {
                        if at(j + 1) == c { j += 2; continue }
                        closed = true; break
                    }
                    j += 1
                }
                guard closed else { return nil }
                current.append(contentsOf: "''".unicodeScalars); i = j + 1
            case "[":
                guard let close = chars[(i + 1)...].firstIndex(of: "]") else { return nil }
                current.append(contentsOf: "''".unicodeScalars); i = close + 1
            case "-" where at(i + 1) == "-":
                while i < chars.count, chars[i] != "\n", chars[i] != "\r" { i += 1 }
            case "/" where at(i + 1) == "*":
                var j = i + 2, closed = false
                while j + 1 < chars.count { if chars[j] == "*" && chars[j + 1] == "/" { closed = true; break }; j += 1 }
                guard closed else { return nil }
                current.append(" "); i = j + 2
            case ";":
                statements.append(String(current)); current = String.UnicodeScalarView(); i += 1
            default:
                current.append(c); i += 1
            }
        }
        statements.append(String(current))
        return statements.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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
