import SwiftUI
import CloudflareKit

struct OverviewView: View {
    @Environment(DomainsStore.self) private var domains
    @Environment(SettingsStore.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.nepheleTheme) private var theme

    var body: some View {
        let sections = settings.settings.overview
        ScrollView {
            VStack(alignment: .leading, spacing: theme.pad) {
                if !(sections.stats || sections.domains) {
                    EmptyStateView(title: "Nothing to show", message: "Every Overview section is hidden. Turn them back on in Appearance.", symbol: "square.grid.2x2")
                }
                LoadStateView(state: domains.zones, permission: "Zone Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No domains yet", emptyMessage: "Add a domain to Cloudflare and it shows up here.", emptySymbol: "globe",
                              retry: { Task { await domains.load(force: true) } }) { zones in
                    if sections.stats { stats(zones) }
                    if sections.domains { domainList(zones) }
                }
            }
            .padding(theme.pad)
        }
        .task { await domains.load() }
    }

    private func stats(_ zones: [Zone]) -> some View {
        let attention = zones.filter { !$0.isActive }.count
        return HStack(spacing: 0) {
            MetricTile(label: "Domains", value: "\(zones.count)", caption: "\(zones.filter(\.isActive).count) active", emphasized: true)
            Divider()
            MetricTile(label: "Needs attention", value: "\(attention)", caption: attention == 0 ? "All domains active" : "Pending or paused")
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: theme.radius))
        .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(.quaternary))
    }

    private func domainList(_ zones: [Zone]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Domains").font(.headline); Spacer(); Button("All domains") { navigator.selection = .domains }.buttonStyle(.link) }
                .padding(theme.pad)
            Divider()
            ForEach(zones) { zone in
                DomainRow(zone: zone).padding(.horizontal, theme.pad).padding(.vertical, theme.rowPad / 2)
                Divider()
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: theme.radius))
        .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(.quaternary))
    }
}
