import Foundation
import CloudflareKit

/// Sample data for `Nephele --demo`: answers every Cloudflare request locally so the app can be explored (and
/// photographed for the docs) without an account. Nothing leaves the Mac and nothing is written to the Keychain.
final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let body = DemoData.reply(method: request.httpMethod ?? "GET", path: url.path, query: url.query ?? "", body: requestBody())
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func requestBody() -> String {
        if let d = request.httpBody { return String(decoding: d, as: UTF8.self) }
        guard let s = request.httpBodyStream else { return "" }
        s.open(); defer { s.close() }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
        return String(decoding: data, as: UTF8.self)
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: config)
    }
}

enum DemoData {
    static let token = "cfut_" + String(repeating: "d", count: 40) + "demo"
    static let zoneNames = ["paper-lantern.example", "harbourlight.example", "northfield-studio.example", "tidepool.example"]

    static func ok(_ result: String) -> String { "{\"success\":true,\"errors\":[],\"result\":\(result),\"result_info\":{\"page\":1,\"per_page\":100,\"total_pages\":1,\"total_count\":1}}" }

    static var zones: String {
        "[" + zoneNames.enumerated().map { i, n in
            "{\"id\":\"z\(i + 1)\",\"name\":\"\(n)\",\"status\":\"\(i == 3 ? "pending" : "active")\",\"paused\":false,\"name_servers\":[\"ada.ns.example.net\",\"lou.ns.example.net\"],\"plan\":{\"name\":\"\(i == 1 ? "Pro" : "Free")\"},\"account\":{\"id\":\"acc1\"}}"
        }.joined(separator: ",") + "]"
    }

    static func dns(_ zone: String) -> String {
        let n = zoneNames[(Int(zone.dropFirst()) ?? 1) - 1]
        return "[{\"id\":\"r1\",\"type\":\"A\",\"name\":\"\(n)\",\"content\":\"192.0.2.10\",\"proxied\":true,\"ttl\":1},{\"id\":\"r2\",\"type\":\"AAAA\",\"name\":\"\(n)\",\"content\":\"2001:db8::10\",\"proxied\":true,\"ttl\":1},{\"id\":\"r3\",\"type\":\"CNAME\",\"name\":\"www.\(n)\",\"content\":\"\(n)\",\"proxied\":true,\"ttl\":1},{\"id\":\"r4\",\"type\":\"CNAME\",\"name\":\"docs.\(n)\",\"content\":\"paper-lantern.pages.dev\",\"proxied\":true,\"ttl\":1},{\"id\":\"r5\",\"type\":\"MX\",\"name\":\"\(n)\",\"content\":\"mail.\(n)\",\"proxied\":false,\"ttl\":3600,\"priority\":10},{\"id\":\"r6\",\"type\":\"TXT\",\"name\":\"\(n)\",\"content\":\"v=spf1 include:_spf.example.net ~all\",\"proxied\":false,\"ttl\":3600}]"
    }

    static let history = "[{\"id\":\"e1\",\"name\":\"Origin error rate spike\",\"alert_type\":\"http_alert_origin_error\",\"policy_id\":\"p1\",\"sent\":\"2026-11-21T14:02:00Z\"},{\"id\":\"e2\",\"name\":\"Certificate expires soon\",\"alert_type\":\"universal_ssl_event_type\",\"policy_id\":\"p2\",\"sent\":\"2026-11-20T10:00:00Z\"},{\"id\":\"e3\",\"name\":\"Worker deploy succeeded\",\"alert_type\":\"workers_alert\",\"policy_id\":\"p3\",\"sent\":\"2026-11-19T09:30:00Z\"}]"

    static var hourly: String {
        let rows = (0..<24).map { h in "{\"dimensions\":{\"datetime\":\"2026-11-21T\(String(format: "%02d", h)):00:00Z\"},\"sum\":{\"requests\":\(30_000 + Int(12_000 * sin(Double(h) / 3.0)) + h * 400),\"cachedRequests\":\(21_000),\"threats\":\(h % 5)}}" }.joined(separator: ",")
        return "{\"data\":{\"viewer\":{\"zones\":[{\"httpRequests1hGroups\":[\(rows)]}]}},\"errors\":null}"
    }
    static let meters = "{\"data\":{\"viewer\":{\"accounts\":[{\"workersInvocationsAdaptive\":[{\"sum\":{\"requests\":62000}}],\"kvOperationsAdaptiveGroups\":[{\"sum\":{\"requests\":91000},\"dimensions\":{\"actionType\":\"read\"}}],\"d1AnalyticsAdaptiveGroups\":[{\"sum\":{\"rowsRead\":1200000,\"rowsWritten\":3000}}],\"r2StorageAdaptiveGroups\":[{\"max\":{\"payloadSize\":1500000000,\"metadataSize\":0},\"dimensions\":{\"bucketName\":\"media\",\"datetime\":\"2026-11-21T14:00:00Z\"}}]}]}},\"errors\":null}"

    static let settings = "[{\"id\":\"ssl\",\"value\":\"full\",\"editable\":true},{\"id\":\"always_use_https\",\"value\":\"on\",\"editable\":true},{\"id\":\"automatic_https_rewrites\",\"value\":\"on\",\"editable\":true},{\"id\":\"min_tls_version\",\"value\":\"1.2\",\"editable\":true},{\"id\":\"tls_1_3\",\"value\":\"on\",\"editable\":true},{\"id\":\"security_level\",\"value\":\"medium\",\"editable\":true},{\"id\":\"development_mode\",\"value\":\"off\",\"editable\":true}]"

    /// Everything the app asks for, keyed by the end of the path. Unknown reads get an empty list.
    static func reply(method: String, path: String, query: String, body: String) -> String {
        if method != "GET" && !path.hasSuffix("/graphql") { return ok("{\"id\":\"demo\"}") }
        let has = { (s: String) in path.hasSuffix(s) }
        if has("/tokens/verify") { return ok("{\"id\":\"tok1\",\"status\":\"active\"}") }
        if has("/accounts") { return ok("[{\"id\":\"acc1\",\"name\":\"Nephele demo\"}]") }
        if has("/zones") { return ok(zones) }
        if path.contains("/dns_records") { return ok(dns(path.split(separator: "/").dropFirst(3).first.map(String.init) ?? "z1")) }
        if has("/graphql") { return body.contains("httpRequests1h") ? hourly : meters }
        if has("/alerting/v3/history") { return ok(history) }
        if has("/workers/scripts") { return ok("[{\"id\":\"edge-router\",\"handlers\":[\"fetch\"],\"modified_on\":\"2026-11-20T10:00:00Z\"},{\"id\":\"nightly-report\",\"handlers\":[\"scheduled\"],\"modified_on\":\"2026-11-18T08:00:00Z\"},{\"id\":\"image-resizer\",\"handlers\":[\"fetch\"],\"modified_on\":\"2026-11-12T16:20:00Z\"}]") }
        if has("/kv/namespaces") { return ok("[{\"id\":\"ns1\",\"title\":\"SESSIONS\"},{\"id\":\"ns2\",\"title\":\"FEATURE_FLAGS\"}]") }
        if has("/d1/database") { return ok("[{\"uuid\":\"db-1\",\"name\":\"orders\",\"version\":\"production\",\"created_at\":\"2026-06-01T10:00:00Z\"},{\"uuid\":\"db-2\",\"name\":\"analytics\",\"created_at\":\"2026-09-10T10:00:00Z\"}]") }
        if has("/r2/buckets") { return ok("{\"buckets\":[{\"name\":\"media\",\"creation_date\":\"2026-03-01T10:00:00Z\"},{\"name\":\"backups\",\"creation_date\":\"2026-05-01T10:00:00Z\"}]}") }
        if has("/cfd_tunnel") { return ok("[{\"id\":\"t1\",\"name\":\"homelab\",\"status\":\"healthy\",\"connections\":[{\"colo_name\":\"LHR\"},{\"colo_name\":\"AMS\"}]},{\"id\":\"t2\",\"name\":\"staging\",\"status\":\"inactive\"}]") }
        if has("/access/apps") { return ok("[{\"id\":\"a1\",\"name\":\"Vaultwarden\",\"domain\":\"vault.paper-lantern.example\",\"type\":\"self_hosted\",\"session_duration\":\"24h\",\"policies\":[{\"id\":\"p\"}]},{\"id\":\"a2\",\"name\":\"Grafana\",\"domain\":\"metrics.paper-lantern.example\",\"type\":\"self_hosted\",\"session_duration\":\"8h\",\"policies\":[{\"id\":\"p\"},{\"id\":\"q\"}]}]") }
        if has("/service_tokens") { return ok("[{\"id\":\"s1\",\"name\":\"ci-deploy\",\"client_id\":\"3f2a1b.access\",\"expires_at\":\"2027-06-01T00:00:00Z\"}]") }
        if has("/gateway/rules") { return ok("[{\"id\":\"g1\",\"name\":\"Block malware domains\",\"action\":\"block\",\"enabled\":true,\"filters\":[\"dns\"],\"precedence\":10},{\"id\":\"g2\",\"name\":\"Allow office network\",\"action\":\"allow\",\"enabled\":true,\"filters\":[\"l4\"],\"precedence\":20}]") }
        if has("/challenges/widgets") { return ok("[{\"sitekey\":\"0x4AAAAAAADemoKey\",\"name\":\"Sign-up form\",\"mode\":\"managed\",\"domains\":[\"paper-lantern.example\"]}]") }
        if has("/pages/projects") { return ok("[{\"name\":\"paper-lantern\",\"subdomain\":\"paper-lantern.pages.dev\",\"domains\":[\"docs.paper-lantern.example\"],\"production_branch\":\"main\"}]") }
        if has("/deployments") { return ok("[{\"id\":\"d1\",\"short_id\":\"a1b2c3d\",\"environment\":\"production\",\"created_on\":\"2026-11-20T09:00:00Z\",\"latest_stage\":{\"name\":\"deploy\",\"status\":\"success\"},\"deployment_trigger\":{\"metadata\":{\"branch\":\"main\",\"commit_message\":\"Update the pricing page\"}}},{\"id\":\"d2\",\"short_id\":\"e4f5a6b\",\"environment\":\"preview\",\"created_on\":\"2026-11-19T15:00:00Z\",\"latest_stage\":{\"name\":\"deploy\",\"status\":\"success\"},\"deployment_trigger\":{\"metadata\":{\"branch\":\"redesign\",\"commit_message\":\"Try a darker header\"}}}]") }
        if has("/zones/z1/settings") || path.hasSuffix("/settings") && path.contains("/zones/") { return ok(settings) }
        if has("/email/routing/rules") { return ok("[{\"id\":\"m1\",\"name\":\"Forward hello\",\"enabled\":true,\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"hello@paper-lantern.example\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"me@example.net\"]}]},{\"id\":\"m2\",\"name\":\"Forward billing\",\"enabled\":false,\"matchers\":[{\"type\":\"literal\",\"field\":\"to\",\"value\":\"billing@paper-lantern.example\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"me@example.net\"]}]}]") }
        if has("/email/routing/addresses") { return ok("[{\"id\":\"d1\",\"email\":\"me@example.net\",\"verified\":\"2026-01-01T00:00:00Z\"}]") }
        if has("/email/routing") { return ok("{\"enabled\":true,\"status\":\"ready\"}") }
        if has("/entrypoint") { return ok("{\"id\":\"rs1\",\"rules\":[{\"id\":\"w1\",\"action\":\"managed_challenge\",\"expression\":\"(http.request.uri.path contains \\\"/wp-login.php\\\")\",\"description\":\"Challenge WordPress login probes\",\"enabled\":true},{\"id\":\"w2\",\"action\":\"block\",\"expression\":\"(ip.geoip.asnum eq 64496)\",\"description\":\"Block a noisy network\",\"enabled\":true}]}") }
        return ok("[]")
    }
}

extension Session {
    /// Signs in against the demo network without saving anything.
    func startDemo() async { await signInForDemo(token: DemoData.token) }
}
