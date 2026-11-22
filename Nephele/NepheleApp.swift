import SwiftUI
import CloudflareKit

@main
struct NepheleApp: App {
    @State private var session: Session
    @State private var domains: DomainsStore
    @State private var alerts: AlertsStore
    @State private var usage: UsageStore
    @State private var workers: WorkersStore
    @State private var storage: StorageStore
    @State private var zeroTrust: ZeroTrustStore
    @State private var pages: PagesStore
    @State private var turnstile: TurnstileStore
    @State private var updates = UpdateModel()
    @State private var poller: AlertPoller
    @State private var settings = SettingsStore()
    @State private var navigator = Navigator()

    init() {
        let demo = AppEnvironment.isDemo
        let session = demo ? Session(tokenStore: TokenStore(service: "io.github.ol775.nephele.demo-unused"), makeClient: { CFClient(token: $0, session: DemoURLProtocol.makeSession()) }) : Session()
        _session = State(initialValue: session)
        let settings = demo ? Self.demoSettings() : SettingsStore()
        let alerts = AlertsStore(session: session)
        _settings = State(initialValue: settings)
        let domains = DomainsStore(session: session)
        _domains = State(initialValue: domains)
        _usage = State(initialValue: UsageStore(session: session, domains: domains))
        _alerts = State(initialValue: alerts)
        _workers = State(initialValue: WorkersStore(session: session))
        _storage = State(initialValue: StorageStore(session: session))
        _zeroTrust = State(initialValue: ZeroTrustStore(session: session))
        _pages = State(initialValue: PagesStore(session: session))
        _turnstile = State(initialValue: TurnstileStore(session: session))
        _poller = State(initialValue: AlertPoller(store: alerts, session: session, settings: settings))
    }

    /// `--demo` keeps its own throwaway settings so it never touches the real ones; `--theme=dark|light`, `--accent=#RRGGBB` and `--route=name` set up screenshots.
    private static func demoSettings() -> SettingsStore {
        let suite = "io.github.ol775.nephele.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        func arg(_ name: String) -> String? { CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) } }
        store.update {
            if let t = arg("theme").flatMap(ThemeChoice.init(rawValue:)) { $0.theme = t }
            if let a = arg("accent") { $0.accentHex = a }
            if let r = arg("route").flatMap(Route.init(rawValue:)) { $0.landing = r }
            $0.showMenuBar = false; $0.autoUpdate = false
        }
        return store
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if session.state == .ready { AppShell() } else { SignInView() }
            }
            .environment(settings)
            .environment(session)
            .environment(navigator)
            .environment(domains)
            .environment(alerts)
            .environment(usage)
            .environment(workers)
            .environment(storage)
            .environment(zeroTrust)
            .environment(pages)
            .environment(turnstile)
            .environment(updates)
            .environment(\.nepheleTheme, NepheleTheme(settings.settings))
            .frame(minWidth: 860, minHeight: 560)
            .task { if AppEnvironment.isDemo { await session.startDemo() } else if !AppEnvironment.isRunningTests { await session.restoreWithRetry() } }
            .task {
                guard AppEnvironment.isDemo, let dir = DemoSnapshots.directory else { return }
                let zone = Zone(id: "z1", name: DemoData.zoneNames[0], status: "active", planName: "Free", nameServers: [], accountID: "acc1")
                await DemoSnapshots.run(into: dir, navigator: navigator, session: session, zone: zone,
                                        routes: [.overview, .domains, .workers, .storage, .zeroTrust, .turnstile, .pages, .alerts, .usage, .appearance, .settings],
                                        zoneScreens: ["dns", "firewall", "email", "zone-settings"])
            }
            .task { if settings.settings.autoUpdate && !AppEnvironment.isRunningTests && !AppEnvironment.isDemo { updates.check() } }
            .task(id: session.state) { if session.state == .ready && !AppEnvironment.isRunningTests && !AppEnvironment.isDemo { poller.start() } else { poller.stop() } }
            .onChange(of: session.identityEpoch) { domains.reset(); alerts.reset(); usage.reset(); workers.reset(); storage.reset(); zeroTrust.reset(); pages.reset(); turnstile.reset() }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") { navigator.openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { navigator.openSettings(); updates.check() }
            }
            CommandGroup(after: .textEditing) {
                Button("Search domains") { navigator.searchDomains() }.keyboardShortcut("k", modifiers: .command)
            }
        }
        MenuBarExtra("Nephele", systemImage: "cloud", isInserted: settings.binding(\.showMenuBar)) {
            MenuBarContent()
                .environment(alerts).environment(domains).environment(navigator).environment(session)
        }
    }
}
