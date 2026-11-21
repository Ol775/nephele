import SwiftUI
import CloudflareKit

extension AlertSeverity {
    var dotKind: StatusDot.Kind { switch self { case .critical: .bad; case .warning: .warning; case .info: .muted } }
    var label: String { switch self { case .critical: "Critical"; case .warning: "Warning"; case .info: "Info" } }
}

struct AlertsView: View {
    @Environment(AlertsStore.self) private var alerts
    @Environment(\.nepheleTheme) private var theme
    @State private var showAll = false
    @State private var showPolicies = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $showAll) { Text("Open (\(alerts.openCount))").tag(false); Text("All").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Spacer()
                Button("Notification rules", systemImage: "bell") { showPolicies = true }
            }
            .padding(theme.pad)
            Divider()
            LoadStateView(state: alerts.events, permission: "Notifications Read",
                          retry: { Task { await alerts.load() } }) { events in
                let shown = showAll ? events : events.filter { !alerts.acknowledged.contains($0.id) }
                if shown.isEmpty {
                    EmptyStateView(title: "You're all clear", message: "No open alerts across your domains. New ones show here and in the menu bar.", symbol: "checkmark.circle")
                } else {
                    List(shown) { event in AlertRow(event: event, acknowledged: alerts.acknowledged.contains(event.id)) { alerts.acknowledge(event.id) } }
                }
            }
        }
        .task { await alerts.load() }
        .sheet(isPresented: $showPolicies) { PoliciesSheet() }
    }
}

struct AlertRow: View {
    let event: AlertEvent
    let acknowledged: Bool
    let acknowledge: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(kind: event.severity.dotKind).help(event.severity.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                Text("\(event.alertType.replacingOccurrences(of: "_", with: " ")) \u{00B7} \(event.sent.formatted(.relative(presentation: .named)))").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if acknowledged { Text("Acknowledged").foregroundStyle(.secondary) } else { Button("Acknowledge", systemImage: "checkmark", action: acknowledge) }
        }
    }
}

private struct PoliciesSheet: View {
    @Environment(AlertsStore.self) private var alerts
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notification rules").font(.headline)
            LoadStateView(state: alerts.policies, permission: "Notifications Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No rules", emptyMessage: "Create notification rules in the Cloudflare dashboard.", emptySymbol: "bell.slash") { policies in
                List(policies) { policy in
                    HStack { StatusDot(kind: policy.enabled ? .ok : .muted); Text(policy.name); Spacer(); Text(policy.enabled ? "On" : "Off").foregroundStyle(.secondary) }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 440, height: 360)
    }
}
