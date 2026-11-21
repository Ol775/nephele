import SwiftUI
import CloudflareKit

struct RangePicker: View {
    let usage: UsageStore
    var body: some View {
        Picker("Range", selection: Binding(get: { usage.range }, set: { r in Task { await usage.setRange(r) } })) {
            ForEach(UsageRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
    }
}

struct UsageView: View {
    @Environment(UsageStore.self) private var usage
    @Environment(\.nepheleTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.pad) {
                HStack { Text("Requests").font(.headline); Spacer(); RangePicker(usage: usage) }
                LoadStateView(state: usage.traffic, permission: "Account Analytics Read", isEmpty: { $0.points.isEmpty },
                              emptyTitle: "No traffic yet", emptyMessage: "Requests to your domains appear here once they start.", emptySymbol: "chart.xyaxis.line",
                              retry: { Task { await usage.load(force: true) } }) { AreaChart(points: $0.points) }
                    .card(theme)
                Text("Against your plan").font(.headline)
                LoadStateView(state: usage.meters, permission: "Account Analytics Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No usage data", emptyMessage: "Usage appears once your Workers, KV, D1 or R2 are used.",
                              retry: { Task { await usage.load(force: true) } }) { meters in
                    VStack(spacing: 0) { ForEach(meters) { MeterRow(meter: $0); Divider() } }
                }
                .card(theme)
                Text("Allowances shown are for the Free plan. Estimated overage is not available from Cloudflare's analytics yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(theme.pad)
        }
        .task { await usage.load() }
    }
}

struct MeterRow: View {
    let meter: Meter
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.label).fontWeight(.medium)
                Spacer()
                Text("\(meter.used.formatted(.number.precision(.fractionLength(0...1)))) of \(meter.limit.formatted()) \(meter.unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: meter.fraction).tint(meter.isHot ? .orange : .accentColor)
                .accessibilityLabel(meter.label).accessibilityValue("\(Int(meter.fraction * 100)) percent used")
        }
        .padding(12)
    }
}

extension View {
    func card(_ theme: NepheleTheme) -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: theme.radius))
            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(.quaternary))
    }
}
