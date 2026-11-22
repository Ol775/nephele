import Foundation

/// How much access to ask for when sending the user to Cloudflare's "create token" page.
/// The dashboard pre-ticks the permissions named in the link; the user still reviews and creates the token.
enum TokenAccess: String, CaseIterable, Identifiable {
    case readOnly, readAndEdit
    var id: String { rawValue }

    var title: String { self == .readOnly ? "Read only" : "Read and edit" }
    var summary: String {
        self == .readOnly
            ? "Browse everything, change nothing. A good place to start."
            : "Also lets Nephele change DNS, settings, Workers, storage and Zero Trust, and purge the cache."
    }

    /// Areas Cloudflare's link format has no short key for (or Nephele can't confirm one for): tick these by hand.
    static let addByHand = "Notifications, Email Routing, WAF, Turnstile, Tunnels and Gateway are not covered by the link, so add those on the dashboard page if you want those screens."

    /// Short keys documented for template links (developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template).
    /// Unknown keys are dropped silently by the dashboard, so only documented ones are used.
    private static let keys = ["zone", "dns", "zone_settings", "account_settings", "account_analytics",
                               "workers_scripts", "workers_kv_storage", "workers_r2", "d1", "page", "access"]

    private var permissions: [(key: String, type: String)] {
        let alwaysRead: Set = ["zone", "account_settings", "account_analytics"]
        var list = Self.keys.map { (key: $0, type: self == .readAndEdit && !alwaysRead.contains($0) ? "edit" : "read") }
        if self == .readAndEdit { list.append((key: "cache", type: "purge")) }
        return list
    }

    var createURL: URL {
        let json = "[" + permissions.map { "{\"key\":\"\($0.key)\",\"type\":\"\($0.type)\"}" }.joined(separator: ",") + "]"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let name = self == .readOnly ? "Nephele (read only)" : "Nephele (read and edit)"
        return URL(string: "https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=\(enc(json))&accountId=%2A&zoneId=all&name=\(enc(name))")!
    }
}
