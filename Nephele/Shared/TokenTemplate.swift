import Foundation

/// How much access to ask for when sending the user to Cloudflare's "create token" page.
/// The dashboard pre-ticks the permissions named in the link; the user still reviews and creates the token.
enum TokenAccess: String, CaseIterable, Identifiable {
    case readOnly, readAndEdit, full
    var id: String { rawValue }

    var title: String { switch self { case .readOnly: "Read only"; case .readAndEdit: "Read and edit"; case .full: "Full access" } }
    var summary: String {
        switch self {
        case .readOnly: "Browse everything, change nothing. A good place to start."
        case .readAndEdit: "Also lets Nephele change DNS, settings, Workers, storage and Access, and purge the cache."
        case .full: "Everything Nephele can do, including Zero Trust Gateway. Use a token you'd be happy to revoke."
        }
    }

    /// Permissions Cloudflare's link format has no key for: tick these by hand on the dashboard page.
    var byHand: String {
        let level = self == .readOnly ? "Read" : "Edit"
        let names = ["Notifications", "Email Routing Rules", "Email Routing Addresses", "Zone WAF", "Turnstile Sites", "Cloudflare Tunnel", "Access: Service Tokens"]
        return "The link can't tick these, so add them on the page: " + names.map { "\($0) \(level)" }.joined(separator: ", ") + "."
    }

    /// Short keys documented for template links (developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template).
    /// Unknown keys are dropped silently by the dashboard, so only documented ones are used.
    private static let keys = ["zone", "dns", "zone_settings", "account_settings", "account_analytics",
                               "workers_scripts", "workers_kv_storage", "workers_r2", "d1", "page", "access"]

    private var permissions: [(key: String, type: String)] {
        let alwaysRead: Set = ["zone", "account_settings", "account_analytics"]
        var list = Self.keys.map { (key: $0, type: self != .readOnly && !alwaysRead.contains($0) ? "edit" : "read") }
        if self != .readOnly { list.append((key: "cache", type: "purge")) }
        if self == .full { list.append((key: "teams", type: "edit")) }
        return list
    }

    var createURL: URL {
        let json = "[" + permissions.map { "{\"key\":\"\($0.key)\",\"type\":\"\($0.type)\"}" }.joined(separator: ",") + "]"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let name = "Nephele (\(title.lowercased()))"
        return URL(string: "https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=\(enc(json))&accountId=%2A&zoneId=all&name=\(enc(name))")!
    }
}
