import SwiftUI
import CloudflareKit

struct OverviewView: View {
    @Environment(DomainsStore.self) private var domains
    @Environment(AlertsStore.self) private var alerts
    @Environment(UsageStore.self) private var usage
    @Environment(SettingsStore.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.nepheleTheme) private var theme

    var body: some View {
        let sections = settings.settings.overview
        ScrollView {
            VStack(alignment: .leading, spacing: theme.pad) {
                if !(sections.stats || sections.chart || sections.alerts || sections.domains) {
                    EmptyStateView(title: "Nothing to show", message: "Every Overview section is hidden. Turn them back on in Appearance.", symbol: "square.grid.2x2")
                }
                if sections.stats || sections.chart { HStack { Spacer(); RangePicker(usage: usage) } }
                if sections.stats { stats }
                if sections.chart { chart }
                if sections.alerts { attentionList }
                if sections.domains { domainsSection }
            }
            .padding(theme.pad)
        }
        .task { await domains.load(); await usage.load(); await alerts.load() }
    }

    private var stats: some View {
        let summary = usage.traffic.value
        let missing = usage.traffic.failure != nil ? "Needs Analytics Read" : nil
        return HStack(spacing: 0) {
            MetricTile(label: "Requests, \(usage.range.rawValue)", value: summary.map { $0.totalRequests.compact } ?? "\u{2014}", caption: missing, emphasized: true)
            Divider()
            MetricTile(label: "Cache hit ratio", value: summary.map { $0.cacheHitRatio.formatted(.percent.precision(.fractionLength(0))) } ?? "\u{2014}")
            Divider()
            MetricTile(label: "Threats blocked", value: summary.map { $0.threats.compact } ?? "\u{2014}")
            Divider()
            MetricTile(label: "Open alerts", value: "\(alerts.openCount)", caption: alerts.openCount == 0 ? "All clear" : "Waiting for you")
        }
        .card(theme)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requests").font(.headline).padding([.top, .horizontal], theme.pad)
            LoadStateView(state: usage.traffic, permission: "Account Analytics Read", isEmpty: { $0.points.isEmpty },
                          emptyTitle: "No traffic yet", emptyMessage: "Requests to your domains appear here.", emptySymbol: "chart.xyaxis.line",
                          retry: { Task { await usage.load(force: true) } }) { AreaChart(points: $0.points).padding([.horizontal, .bottom], theme.pad) }
        }
        .card(theme)
    }

    private var attentionList: some View {
        let open = (alerts.events.value ?? []).filter { !alerts.acknowledged.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Needs attention").font(.headline); Spacer(); Button("All alerts") { navigator.selection = .alerts }.buttonStyle(.link) }.padding(theme.pad)
            Divider()
            if open.isEmpty {
                Text("You're all clear.").foregroundStyle(.secondary).padding(theme.pad)
            } else {
                ForEach(open.prefix(3)) { event in
                    AlertRow(event: event, acknowledged: false) { alerts.acknowledge(event.id) }
                        .padding(.horizontal, theme.pad).padding(.vertical, theme.rowPad / 2)
                    Divider()
                }
            }
        }
        .card(theme)
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Domains").font(.headline); Spacer(); Button("All domains") { navigator.selection = .domains }.buttonStyle(.link) }.padding(theme.pad)
            Divider()
            LoadStateView(state: domains.zones, permission: "Zone Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No domains yet", emptyMessage: "Add a domain to Cloudflare and it shows up here.", emptySymbol: "globe",
                          retry: { Task { await domains.load(force: true) } }) { zones in
                ForEach(zones) { zone in
                    DomainRow(zone: zone).padding(.horizontal, theme.pad).padding(.vertical, theme.rowPad / 2)
                    Divider()
                }
            }
        }
        .card(theme)
    }
}
