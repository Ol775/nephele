import SwiftUI
import CloudflareKit

struct FirewallView: View {
    @State private var store: FirewallStore
    @State private var action = "managed_challenge"
    @State private var expression = ""
    @State private var note = ""

    init(zone: Zone, session: Session) { _store = State(initialValue: FirewallStore(zone: zone, session: session)) }

    private func label(_ r: FirewallRule) -> String { r.description?.isEmpty == false ? r.description! : r.expression }
    private static let actions = [("managed_challenge", "Managed challenge"), ("js_challenge", "JS challenge"), ("challenge", "Interactive challenge"), ("block", "Block"), ("log", "Log")]

    var body: some View {
        VStack(spacing: 0) {
            LoadStateView(state: store.rules, permission: "Zone WAF Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No custom rules", emptyMessage: "Add one below. Rules apply to every visitor of \(store.zone.name) straight away.", emptySymbol: "shield",
                          retry: { Task { await store.load() } }) { list in
                List(list) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.description?.isEmpty == false ? r.description! : "Untitled rule")
                            Text(Self.actions.first { $0.0 == r.action }?.1 ?? r.action).font(.footnote).foregroundStyle(.secondary)
                            Text(r.expression).font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { r.enabled ?? true }, set: { on in
                            if on { store.request(.enable(r)) } else { Task { await store.disable(r) } } })).labelsHidden()
                            .accessibilityLabel("Enabled for \(label(r))").disabled(!store.canWrite || store.busy || !r.isPlain)
                            .help(r.isPlain ? "" : "This rule has options Nephele can't show. Change it in the Cloudflare dashboard.")
                        Button("Delete", systemImage: "trash", role: .destructive) { store.request(.delete(r)) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityLabel("Delete rule \(label(r))").disabled(!store.canWrite || store.busy)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if !store.canWrite { Label("This token can't change WAF rules. Add Zone WAF Edit to it in Cloudflare.", systemImage: "lock").foregroundStyle(.secondary) }
                else if let e = store.formError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                Text("Expressions use Cloudflare's rules language, for example (ip.src eq 203.0.113.7) or (http.request.uri.path contains \"/admin\").").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Picker("Action", selection: $action) { ForEach(Self.actions, id: \.0) { Text($0.1).tag($0.0) } }.frame(maxWidth: 220)
                    TextField("Name", text: $note).frame(maxWidth: 160)
                    TextField("Expression", text: $expression).font(.body.monospaced())
                    Button("Add rule\u{2026}") { store.request(.create(FirewallRuleDraft(action: action, expression: expression, description: note))) }
                        .disabled(!store.canWrite || store.busy || store.rules.value == nil || expression.allSatisfy(\.isWhitespace))
                }
            }.padding(12)
        }
        .navigationTitle("\(store.zone.name) firewall")
        .task { await store.load() }
        .confirmationDialog(store.confirm.pending?.title ?? "", isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }), presenting: store.confirm.pending) { change in
            Button(change.button, role: .destructive) { Task { await store.confirmChange(change); if store.formError == nil, case .create = change { expression = ""; note = "" } } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { Text($0.message) }
    }
}
