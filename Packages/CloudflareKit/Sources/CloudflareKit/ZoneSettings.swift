import Foundation

/// The zone settings Nephele shows. Everything else Cloudflare returns is ignored, so an unknown or structured setting can't break the list.
public enum ZoneSettingID {
    public static let ssl = "ssl", alwaysHTTPS = "always_use_https", rewrites = "automatic_https_rewrites"
    public static let minTLS = "min_tls_version", tls13 = "tls_1_3", devMode = "development_mode", securityLevel = "security_level"
    public static let known: Set<String> = [ssl, alwaysHTTPS, rewrites, minTLS, tls13, devMode, securityLevel]
}

public struct ZoneSetting: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let value: String
    public let editable: Bool
    public init(id: String, value: String, editable: Bool = true) { self.id = id; self.value = value; self.editable = editable }

    private enum CodingKeys: String, CodingKey { case id, value, editable }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        value = try c.decode(String.self, forKey: .value)
        editable = try c.decodeIfPresent(Bool.self, forKey: .editable) ?? true
    }
}

/// One list item that fails to decode (a structured value, say) is skipped rather than failing the whole list.
private struct LossySettings: Decodable, Sendable {
    let items: [ZoneSetting]
    init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [ZoneSetting] = []
        while !c.isAtEnd {
            if let s = try? c.decode(ZoneSetting.self) { if ZoneSettingID.known.contains(s.id) { out.append(s) } }
            else { _ = try? c.decode(JSONValue.self) }
        }
        items = out
    }
}

public enum PurgeScope: Sendable, Equatable { case everything, files([String]) }

public enum PurgeURLError: Error, Equatable, LocalizedError {
    case empty, tooMany, notURL(String)
    public var errorDescription: String? {
        switch self {
        case .empty: "Enter at least one URL."
        case .tooMany: "Cloudflare purges at most 100 URLs at a time."
        case .notURL(let s): "\u{201C}\(s)\u{201D} isn't a full URL. Start it with https://."
        }
    }
}

public enum PurgeURLs {
    public static let limit = 100
    /// One URL per line. Blank lines are ignored.
    public static func parse(_ text: String) -> Result<[String], PurgeURLError> {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .failure(.empty) }
        for l in lines {
            guard let u = URL(string: l), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host?.isEmpty == false else { return .failure(.notURL(l)) }
        }
        return lines.count > limit ? .failure(.tooMany) : .success(lines)
    }
}

private struct SettingValue: Encodable, Sendable { let value: String }
private struct PurgeBody: Encodable, Sendable {
    var purgeEverything: Bool?
    var files: [String]?
}
private struct Ignored: Decodable, Sendable {}

extension CFClient {
    public func zoneSettings(zoneID: String) async throws -> [ZoneSetting] {
        let env: CFEnvelope<LossySettings> = try await get("/zones/\(pathSegment(zoneID))/settings")
        return env.result?.items ?? []
    }

    public func updateZoneSetting(zoneID: String, id: String, value: String) async throws -> ZoneSetting {
        try await send("PATCH", "/zones/\(pathSegment(zoneID))/settings/\(pathSegment(id))", body: SettingValue(value: value))
    }

    public func purgeCache(zoneID: String, _ scope: PurgeScope) async throws {
        let body: PurgeBody = switch scope {
        case .everything: PurgeBody(purgeEverything: true)
        case .files(let f): PurgeBody(files: f)
        }
        let _: Ignored = try await send("POST", "/zones/\(pathSegment(zoneID))/purge_cache", body: body)
    }
}
