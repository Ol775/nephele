import Foundation

public struct TailSession: Sendable, Equatable, Decodable {
    public let id: String
    public let url: URL
    public let expiresAt: String?
    public init(id: String, url: URL, expiresAt: String? = nil) { self.id = id; self.url = url; self.expiresAt = expiresAt }
}

public struct TailLogLine: Sendable, Equatable {
    public let level: String
    public let text: String
}

/// One invocation of a Worker as reported by the live tail.
public struct TailEvent: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let time: Date
    public let outcome: String
    public let method: String?
    public let url: String?
    public let logs: [TailLogLine]
    public let exceptions: [String]

    public static func == (a: TailEvent, b: TailEvent) -> Bool { a.id == b.id }

    public var isError: Bool { outcome != "ok" || !exceptions.isEmpty || logs.contains { $0.level == "error" } }

    /// Parses one message from the tail socket. Returns nil for anything that isn't an invocation event.
    public static func parse(_ data: Data) -> TailEvent? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let outcome = object["outcome"] as? String else { return nil }
        let millis = (object["eventTimestamp"] as? Double) ?? 0
        let request = (object["event"] as? [String: Any])?["request"] as? [String: Any]
        let logs = (object["logs"] as? [[String: Any]] ?? []).map { entry -> TailLogLine in
            let parts = (entry["message"] as? [Any] ?? []).map(describe)
            return TailLogLine(level: entry["level"] as? String ?? "log", text: parts.joined(separator: " "))
        }
        let exceptions = (object["exceptions"] as? [[String: Any]] ?? []).map { "\($0["name"] as? String ?? "Error"): \($0["message"] as? String ?? "")" }
        return TailEvent(time: Date(timeIntervalSince1970: millis / 1000), outcome: outcome, method: request?["method"] as? String,
                         url: request?["url"] as? String, logs: logs, exceptions: exceptions)
    }

    private static func describe(_ value: Any) -> String {
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value), let d = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { return String(decoding: d, as: UTF8.self) }
        return "\(value)"
    }
}

extension CFClient {
    public func startTail(accountID: String, script: String) async throws -> TailSession {
        try await send("POST", "/accounts/\(accountID)/workers/scripts/\(script)/tails", body: JSONValue.object([:]))
    }

    public func stopTail(accountID: String, script: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/workers/scripts/\(script)/tails/\(id)")
    }
}
