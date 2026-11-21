import SwiftUI

@main
struct NepheleApp: App {
    @State private var settings = SettingsStore()
    @State private var session: Session
    @State private var domains: DomainsStore
    @State private var navigator = Navigator()

    init() {
        let session = Session()
        _session = State(initialValue: session)
        _domains = State(initialValue: DomainsStore(session: session))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.state == .ready { AppShell() } else { SignInView() }
            }
            .environment(settings)
            .environment(session)
            .environment(navigator)
            .environment(domains)
            .environment(\.nepheleTheme, NepheleTheme(settings.settings))
            .frame(minWidth: 860, minHeight: 560)
            .task { await session.restore() }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") { navigator.openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Search domains") { navigator.searchDomains() }.keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
