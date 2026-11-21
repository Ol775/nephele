import SwiftUI

@main
struct NepheleApp: App {
    @State private var session: Session
    @State private var domains: DomainsStore
    @State private var alerts: AlertsStore
    @State private var usage: UsageStore
    @State private var poller: AlertPoller
    @State private var settings = SettingsStore()
    @State private var navigator = Navigator()

    init() {
        let session = Session()
        _session = State(initialValue: session)
        let settings = SettingsStore()
        let alerts = AlertsStore(session: session)
        _settings = State(initialValue: settings)
        let domains = DomainsStore(session: session)
        _domains = State(initialValue: domains)
        _usage = State(initialValue: UsageStore(session: session, domains: domains))
        _alerts = State(initialValue: alerts)
        _poller = State(initialValue: AlertPoller(store: alerts, session: session, settings: settings))
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
            .environment(\.nepheleTheme, NepheleTheme(settings.settings))
            .frame(minWidth: 860, minHeight: 560)
            .task { if !AppEnvironment.isRunningTests { await session.restoreWithRetry() } }
            .task(id: session.state) { if session.state == .ready && !AppEnvironment.isRunningTests { poller.start() } else { poller.stop() } }
            .onChange(of: session.identityEpoch) { domains.reset(); alerts.reset(); usage.reset() }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") { navigator.openSettings() }.keyboardShortcut(",", modifiers: .command)
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
