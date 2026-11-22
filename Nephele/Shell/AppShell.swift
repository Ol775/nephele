import SwiftUI

struct AppShell: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        let settings = store.settings
        let theme = NepheleTheme(settings)
        NavigationSplitView {
            List(settings.visibleRoutes, selection: $navigator.selection) { route in
                SidebarRow(route: route, iconsOnly: settings.sidebarIcons)
                    .tag(route)
            }
            .listStyle(.sidebar)
            .background(theme.tintSidebar ? theme.accent.opacity(0.06) : .clear)
            .navigationSplitViewColumnWidth(min: settings.sidebarIcons ? 64 : 180, ideal: settings.sidebarIcons ? 64 : 210, max: settings.sidebarIcons ? 64 : 260)
        } detail: {
            let route = navigator.selection ?? settings.landing
            Group {
                switch route {
                case .overview: OverviewView()
                case .domains: DomainsView()
                case .workers: WorkersView()
                case .storage: StorageView()
                case .zeroTrust: ZeroTrustView()
                case .pages: PagesView()
                case .alerts: AlertsView()
                case .usage: UsageView()
                case .appearance: AppearanceView()
                case .settings: SettingsView()
                default: Placeholder(route: route)
                }
            }
            .navigationTitle(route.title)
        }
        .tint(theme.accent)
        .environment(\.nepheleTheme, theme)
        .font(.system(size: theme.fontSize, design: theme.fontDesign))
        .preferredColorScheme(settings.theme == .system ? nil : (settings.theme == .dark ? .dark : .light))
        .transaction { if settings.reduceMotion { $0.animation = nil } }
        .modifier(ContrastModifier(enabled: settings.highContrast))
        .onAppear { navigator.selection = navigator.selection ?? settings.landing }
    }
}

extension Route: Identifiable { var id: String { rawValue } }

private struct SidebarRow: View {
    let route: Route
    let iconsOnly: Bool
    var body: some View {
        if iconsOnly {
            Image(systemName: route.symbol).help(route.title).accessibilityLabel(route.title)
        } else {
            Label(route.title, systemImage: route.symbol)
        }
    }
}

private struct Placeholder: View {
    let route: Route
    var body: some View {
        ContentUnavailableView(route.title, systemImage: route.symbol, description: Text("Coming together in the next tasks."))
    }
}

private struct ContrastModifier: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.foregroundStyle(.primary, .primary, .primary) } else { content }
    }
}
