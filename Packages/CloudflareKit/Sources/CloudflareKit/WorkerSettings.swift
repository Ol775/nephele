import Foundation

/// A Worker name: 1 to 63 characters, lowercase letters, digits and hyphens, not starting or ending with a hyphen.
public func validWorkerName(_ name: String) -> Bool {
    guard (1...63).contains(name.count) else { return false }
    return name.wholeMatch(of: /[a-z0-9]([a-z0-9-]*[a-z0-9])?/) != nil
}

/// A binding name is a JavaScript identifier: letters, digits, `_` and `$`, not starting with a digit.
public func validBindingName(_ name: String) -> Bool {
    name.wholeMatch(of: /[A-Za-z_$][A-Za-z0-9_$]*/) != nil
}

/// A binding exactly as Cloudflare returned it, so fields we don't understand survive a save.
public struct WorkerBinding: Sendable, Equatable, Identifiable, Codable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(from decoder: any Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: any Encoder) throws { try fields.encode(to: encoder) }

    public var name: String { fields["name"]?.stringValue ?? "" }
    public var type: String { fields["type"]?.stringValue ?? "" }
    public var id: String { name }
    public var text: String? { fields["text"]?.stringValue }
    public var isSecret: Bool { type == "secret_text" || type == "secret_key" }

    public static func plain(name: String, text: String) -> WorkerBinding {
        WorkerBinding(fields: ["name": .string(name), "type": .string("plain_text"), "text": .string(text)])
    }
}

public struct WorkerSettings: Sendable, Equatable {
    public var compatibilityDate: String?
    public var compatibilityFlags: [String]
    public var observabilityEnabled: Bool
    public var bindings: [WorkerBinding]
    public var plainVars: [WorkerBinding] { bindings.filter { $0.type == "plain_text" } }

    public init(compatibilityDate: String? = nil, compatibilityFlags: [String] = [], observabilityEnabled: Bool = false, bindings: [WorkerBinding] = []) {
        self.compatibilityDate = compatibilityDate; self.compatibilityFlags = compatibilityFlags
        self.observabilityEnabled = observabilityEnabled; self.bindings = bindings
    }
}

/// Only the non-nil fields are sent. Secret bindings go as `inherit`, so their values are kept.
public struct WorkerSettingsChange: Sendable, Equatable {
    public var compatibilityDate: String?
    public var compatibilityFlags: [String]?
    public var observabilityEnabled: Bool?
    public var bindings: [WorkerBinding]?
    public init(compatibilityDate: String? = nil, compatibilityFlags: [String]? = nil, observabilityEnabled: Bool? = nil, bindings: [WorkerBinding]? = nil) {
        self.compatibilityDate = compatibilityDate; self.compatibilityFlags = compatibilityFlags
        self.observabilityEnabled = observabilityEnabled; self.bindings = bindings
    }

    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let compatibilityDate { o["compatibility_date"] = .string(compatibilityDate) }
        if let compatibilityFlags { o["compatibility_flags"] = .array(compatibilityFlags.map { .string($0) }) }
        if let observabilityEnabled { o["observability"] = .object(["enabled": .bool(observabilityEnabled)]) }
        if let bindings {
            o["bindings"] = .array(bindings.map { b in
                b.isSecret ? .object(["name": .string(b.name), "type": .string("inherit")]) : .object(b.fields)
            })
        }
        return .object(o)
    }
}

private struct RawSettings: Decodable {
    struct Observability: Decodable { let enabled: Bool? }
    let compatibilityDate: String?
    let compatibilityFlags: [String]?
    let observability: Observability?
    let bindings: [WorkerBinding]?
    private enum CodingKeys: String, CodingKey { case compatibilityDate = "compatibility_date", compatibilityFlags = "compatibility_flags", observability, bindings }
}
private struct RawEnvelope<T: Decodable>: Decodable { let result: T }
private struct Named: Decodable, Sendable { let name: String }
private struct EnabledFlag: Decodable, Sendable { let enabled: Bool }

private func decodeSettings(_ data: Data) throws -> WorkerSettings {
    do {
        let r = try JSONDecoder().decode(RawEnvelope<RawSettings>.self, from: data).result
        return WorkerSettings(compatibilityDate: r.compatibilityDate, compatibilityFlags: r.compatibilityFlags ?? [],
                              observabilityEnabled: r.observability?.enabled ?? false, bindings: r.bindings ?? [])
    } catch { throw CloudflareError.decoding("settings") }
}

extension CFClient {
    private func scriptPath(_ account: String, _ script: String) -> String { "/accounts/\(account)/workers/scripts/\(script)" }

    public func workerSettings(accountID: String, script: String) async throws -> WorkerSettings {
        try decodeSettings(try await raw("GET", scriptPath(accountID, script) + "/settings"))
    }

    public func updateWorkerSettings(accountID: String, script: String, _ change: WorkerSettingsChange) async throws -> WorkerSettings {
        var form = MultipartForm()
        form.addJSON(name: "settings", try JSONEncoder().encode(change.json))
        let data = try await raw("PATCH", scriptPath(accountID, script) + "/settings", body: form.body, contentType: form.contentType)
        return try decodeSettings(data)
    }

    public func workerSecretNames(accountID: String, script: String) async throws -> [String] {
        let env: CFEnvelope<[Named]> = try await get(scriptPath(accountID, script) + "/secrets")
        return (env.result ?? []).map(\.name)
    }

    public func setWorkerSecret(accountID: String, script: String, name: String, value: String) async throws {
        let body = try JSONEncoder().encode(JSONValue.object(["name": .string(name), "text": .string(value), "type": .string("secret_text")]))
        _ = try await raw("PUT", scriptPath(accountID, script) + "/secrets", body: body)
    }

    public func deleteWorkerSecret(accountID: String, script: String, name: String) async throws {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        _ = try await raw("DELETE", scriptPath(accountID, script) + "/secrets/\(escaped)")
    }

    public func workersDevSubdomain(accountID: String, script: String) async throws -> Bool {
        let env: CFEnvelope<EnabledFlag> = try await get(scriptPath(accountID, script) + "/subdomain")
        return env.result?.enabled ?? false
    }

    public func setWorkersDevSubdomain(accountID: String, script: String, enabled: Bool) async throws {
        let body = try JSONEncoder().encode(JSONValue.object(["enabled": .bool(enabled)]))
        _ = try await raw("POST", scriptPath(accountID, script) + "/subdomain", body: body)
    }
}
