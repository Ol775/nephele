import SwiftUI
import CloudflareKit

extension Zone {
    var isActive: Bool { status == "active" && !paused }
    var statusLabel: String { paused ? "Paused" : status.prefix(1).uppercased() + status.dropFirst() }
    var statusKind: StatusDot.Kind { isActive ? .ok : .warning }
}

struct DomainsView: View {
    @Environment(DomainsStore.self) private var domains
    @Environment(Session.self) private var session
    @Environment(Navigator.self) private var navigator
    @Environment(\.nepheleTheme) private var theme
    @State private var query = ""
    @State private var onlyAttention = false
    @State private var searching = false

    var body: some View {
        NavigationStack {
            LoadStateView(state: domains.zones, permission: "Zone Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No domains yet", emptyMessage: "Add a domain to Cloudflare and it shows up here.", emptySymbol: "globe",
                          retry: { Task { await domains.load(force: true) } }) { zones in
                let shown = zones.filter { zone in
                    (!onlyAttention || !zone.isActive) && (query.isEmpty || zone.name.localizedCaseInsensitiveContains(query))
                }
                if shown.isEmpty {
                    EmptyStateView(title: onlyAttention && query.isEmpty ? "Nothing needs attention" : "No domains match", message: onlyAttention && query.isEmpty ? "Every domain is active." : "Check the spelling, or clear the filter.", symbol: "checkmark.circle")
                } else {
                    List(shown) { zone in
                        NavigationLink(value: zone) { DomainRow(zone: zone) }
                    }
                }
            }
            .searchable(text: $query, isPresented: $searching, prompt: "Filter domains")
            .toolbar {
                ToolbarItem { Toggle("Needs attention", systemImage: "exclamationmark.circle", isOn: $onlyAttention) }
                ToolbarItem { Button("Refresh", systemImage: "arrow.clockwise") { Task { await domains.load(force: true) } } }
            }
            .navigationDestination(for: Zone.self) { DNSDetailView(zone: $0, session: session) }
        }
        .task { await domains.load() }
        .onChange(of: navigator.searchRequest) { searching = true }
    }
}

struct DomainRow: View {
    let zone: Zone
    var body: some View {
        HStack(spacing: 12) {
            Text(zone.name.prefix(1).uppercased()).font(.caption.bold()).frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.tint)
            Text(zone.name).fontWeight(.medium)
            Spacer()
            HStack(spacing: 6) { StatusDot(kind: zone.statusKind); Text(zone.statusLabel) }.foregroundStyle(.secondary)
            Text(zone.planName).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}
