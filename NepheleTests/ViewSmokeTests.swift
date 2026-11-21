import Testing
import SwiftUI
import AppKit
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

/// Renders each screen with realistic fake data. Catches missing environment objects and layout crashes,
/// and writes PNGs to the app container's temp folder for a visual check.
@MainActor
@Suite(.serialized) struct ViewSmokeTests {
    nonisolated static let zones = (1...4).map { "{\"id\":\"z\($0)\",\"name\":\"example-\($0).dev\",\"status\":\"\($0 == 4 ? "pending" : "active")\",\"paused\":false,\"name_servers\":[],\"plan\":{\"name\":\"\($0 == 2 ? "Pro" : "Free")\"},\"account\":{\"id\":\"acc1\"}}" }.joined(separator: ",")
    nonisolated static let dns = "[{\"id\":\"r1\",\"type\":\"A\",\"name\":\"example-1.dev\",\"content\":\"192.0.2.10\",\"proxied\":true,\"ttl\":1},{\"id\":\"r2\",\"type\":\"CNAME\",\"name\":\"www.example-1.dev\",\"content\":\"example-1.dev\",\"proxied\":true,\"ttl\":1},{\"id\":\"r3\",\"type\":\"MX\",\"name\":\"example-1.dev\",\"content\":\"mail.example-1.dev\",\"proxied\":false,\"ttl\":1,\"priority\":10}]"
    nonisolated static let history = "[{\"id\":\"e1\",\"name\":\"Origin error rate spike\",\"alert_type\":\"http_alert_origin_error\",\"policy_id\":\"p\",\"sent\":\"2026-11-21T14:02:00Z\"},{\"id\":\"e2\",\"name\":\"Certificate expires soon\",\"alert_type\":\"universal_ssl_event_type\",\"policy_id\":\"p\",\"sent\":\"2026-11-20T10:00:00Z\"}]"
    nonisolated static var hourly: String {
        let rows = (0..<24).map { h in "{\"dimensions\":{\"datetime\":\"2026-11-21T\(String(format: "%02d", h)):00:00Z\"},\"sum\":{\"requests\":\(30_000 + Int(12_000 * sin(Double(h) / 3.0)) + h * 400),\"cachedRequests\":\(20_000),\"threats\":\(h % 5)}}" }.joined(separator: ",")
        return "{\"data\":{\"viewer\":{\"zones\":[{\"httpRequests1hGroups\":[\(rows)]}]}},\"errors\":null}"
    }
    nonisolated static let meters = "{\"data\":{\"viewer\":{\"accounts\":[{\"workersInvocationsAdaptive\":[{\"sum\":{\"requests\":62000}}],\"kvOperationsAdaptiveGroups\":[{\"sum\":{\"requests\":91000},\"dimensions\":{\"actionType\":\"read\"}}],\"d1AnalyticsAdaptiveGroups\":[{\"sum\":{\"rowsRead\":1200000,\"rowsWritten\":3000}}],\"r2StorageAdaptiveGroups\":[{\"max\":{\"payloadSize\":1500000000,\"metadataSize\":0},\"dimensions\":{\"bucketName\":\"media\",\"datetime\":\"2026-11-21T14:00:00Z\"}}]}]}},\"errors\":null}"

    struct World {
        let session: Session, settings: SettingsStore, nav: Navigator, domains: DomainsStore, alerts: AlertsStore, usage: UsageStore, workers: WorkersStore, storage: StorageStore
    }

    func world() async throws -> World {
        let stub = StubServer { req in
            let path = req.url!.path
            if path.hasSuffix("/zones"), req.url?.query?.contains("per_page=50") == true { return TestAPI.reply(req, TestAPI.ok("[\(Self.zones)]")) }
            if path.contains("/dns_records") { return TestAPI.reply(req, TestAPI.ok(Self.dns)) }
            if path.hasSuffix("/workers/scripts") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"hello-api\",\"handlers\":[\"fetch\"]},{\"id\":\"cron-job\",\"handlers\":[\"scheduled\"]}]")) }
            if path.hasSuffix("/kv/namespaces") { return TestAPI.reply(req, TestAPI.ok("[{\"id\":\"ns1\",\"title\":\"CACHE\"},{\"id\":\"ns2\",\"title\":\"SESSIONS\"}]")) }
            if path.hasSuffix("/d1/database") { return TestAPI.reply(req, TestAPI.ok("[{\"uuid\":\"db-1\",\"name\":\"app-db\"}]")) }
            if path.hasSuffix("/r2/buckets") { return TestAPI.reply(req, TestAPI.ok("{\"buckets\":[{\"name\":\"media\"}]}")) }
            if path.hasSuffix("/schedules") { return TestAPI.reply(req, TestAPI.ok("{\"schedules\":[{\"cron\":\"*/30 * * * *\"}]}")) }
            if path.hasSuffix("/alerting/v3/history") { return TestAPI.reply(req, TestAPI.ok(Self.history)) }
            if path.hasSuffix("/graphql") {
                let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
                return TestAPI.reply(req, body.contains("httpRequests1h") ? Self.hourly : Self.meters)
            }
            return TestAPI.base(req)
        }
        let session = try await TestAPI.readySession(stub)
        let defaults = UserDefaults(suiteName: "nephele.tests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let domains = DomainsStore(session: session)
        let alerts = AlertsStore(session: session, defaults: defaults)
        let usage = UsageStore(session: session, domains: domains)
        await usage.load(); await alerts.load()
        return World(session: session, settings: settings, nav: Navigator(), domains: domains, alerts: alerts, usage: usage, workers: WorkersStore(session: session), storage: StorageStore(session: session))
    }

    func render<V: View>(_ name: String, _ view: V, _ w: World, size: CGSize = CGSize(width: 1100, height: 720)) throws -> Int {
        let root = view
            .environment(w.settings).environment(w.session).environment(w.nav).environment(w.domains).environment(w.alerts).environment(w.usage).environment(w.workers).environment(w.storage)
            .environment(\.nepheleTheme, NepheleTheme(w.settings.settings))
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nephele-snaps")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
        return png.count
    }

    @Test func overviewRenders() async throws {
        let w = try await world(); await w.domains.load()
        #expect(try render("overview", OverviewView(), w) > 5_000)
    }
    @Test func domainsRenders() async throws {
        let w = try await world(); await w.domains.load()
        #expect(try render("domains", DomainsView(), w) > 5_000)
    }
    @Test func dnsDetailRenders() async throws {
        let w = try await world()
        #expect(try render("dns", NavigationStack { DNSDetailView(zone: TestAPI.zone, session: w.session) }, w) > 5_000)
    }
    @Test func workersRenders() async throws {
        let w = try await world(); await w.workers.load()
        #expect(try render("workers", WorkersView(), w) > 5_000)
    }
    @Test func workerDetailRenders() async throws {
        let w = try await world()
        #expect(try render("worker-detail", NavigationStack { WorkerDetailView(script: WorkerScript(id: "hello-api", compatibilityDate: "2026-10-01")) }, w) > 5_000)
    }
    @Test func workerSettingsRenders() async throws {
        let w = try await world()
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: w.session)
        await store.loadSettings()
        #expect(try render("worker-settings", WorkerSettingsView(store: store), w) > 5_000)
    }
    @Test func workerTriggersRenders() async throws {
        let w = try await world(); await w.domains.load()
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: w.session)
        await store.loadTriggers(zones: w.domains.zones.value ?? [])
        #expect(try render("worker-triggers", WorkerTriggersView(store: store), w) > 5_000)
    }
    @Test func workerVersionsRenders() async throws {
        let w = try await world()
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: w.session)
        await store.loadVersions()
        #expect(try render("worker-versions", WorkerVersionsView(store: store), w) > 5_000)
    }
    @Test func workerCodeRenders() async throws {
        let w = try await world()
        let store = WorkerStore(script: WorkerScript(id: "hello-api"), session: w.session)
        #expect(try render("worker-code", WorkerCodeView(store: store), w) > 5_000)
    }
    @Test func workerLogsRenders() async throws {
        let w = try await world()
        #expect(try render("worker-logs", WorkerLogsView(script: "hello-api", session: w.session), w) > 5_000)
    }
    @Test func newAndDeleteWorkerSheetsRender() async throws {
        let w = try await world()
        let ws = WorkersStore(session: w.session)
        #expect(try render("new-worker", NewWorkerSheet(workers: ws) { _ in }, w, size: CGSize(width: 460, height: 320)) > 3_000)
        #expect(try render("delete-worker", DeleteWorkerSheet(workers: ws, script: WorkerScript(id: "hello-api")) {}, w, size: CGSize(width: 460, height: 260)) > 3_000)
    }
    @Test func storageRenders() async throws {
        let w = try await world(); await w.storage.kv.load()
        #expect(try render("storage-kv", StorageView(), w) > 5_000)
    }
    @Test func d1Renders() async throws {
        let w = try await world(); await w.storage.d1.load()
        let view = StorageView()
        #expect(try render("storage-d1", view, w) > 5_000)
    }
    @Test func alertsRenders() async throws {
        let w = try await world()
        #expect(try render("alerts", AlertsView(), w) > 5_000)
    }
    @Test func usageRenders() async throws {
        let w = try await world()
        #expect(try render("usage", UsageView(), w) > 5_000)
    }
    @Test func settingsRenders() async throws {
        let w = try await world()
        #expect(try render("settings", SettingsView(), w) > 5_000)
    }
    @Test func appearanceRenders() async throws {
        let w = try await world()
        #expect(try render("appearance", AppearanceView(), w) > 5_000)
    }
    @Test func signInRenders() async throws {
        let w = try await world()
        #expect(try render("signin", SignInView(), w, size: CGSize(width: 700, height: 520)) > 5_000)
    }
    @Test func shellRendersWithRightThemeSettings() async throws {
        let w = try await world()
        w.settings.update { $0.theme = .dark; $0.accentHex = "#7A5AF8"; $0.density = .compact; $0.fontDesign = .rounded; $0.sidebarIcons = true }
        #expect(try render("shell-dark", AppShell(), w) > 5_000)
    }
}
