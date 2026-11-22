import SwiftUI
import CloudflareKit

struct EmailRoutingView: View {
    @State private var store: EmailRoutingStore
    @State private var address = ""
    @State private var destination = ""

    init(zone: Zone, session: Session) { _store = State(initialValue: EmailRoutingStore(zone: zone, session: session)) }

    var body: some View {
        VStack(spacing: 0) {
            if store.routing?.enabled == false { Label("Email Routing is off for this domain. Turn it on in the Cloudflare dashboard.", systemImage: "info.circle").foregroundStyle(.secondary).padding() }
            LoadStateView(state: store.rules, permission: "Email Routing Rules Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No forwarding rules", emptyMessage: "Add one below to forward an address on \(store.zone.name).", emptySymbol: "envelope",
                          retry: { Task { await store.load() } }) { list in
                List(list) { r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.from ?? (r.name?.isEmpty == false ? r.name! : "Catch-all"))
                            Text(r.isForward ? "Forwards to \(r.destinations.joined(separator: ", "))" : (r.actions?.first?.type.capitalized ?? "")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { r.enabled ?? true }, set: { _ in Task { await store.toggle(r) } })).labelsHidden()
                            .accessibilityLabel("Enabled for \(r.from ?? "this rule")").disabled(!store.canWrite || store.busy || r.from == nil)
                        Button("Delete", systemImage: "trash", role: .destructive) { store.requestDelete(r) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityLabel("Delete rule for \(r.from ?? "this rule")").disabled(!store.canWrite || store.busy || r.from == nil)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if !store.canWrite { Label("This token can't change Email Routing. Add Email Routing Rules Edit to it in Cloudflare.", systemImage: "lock").foregroundStyle(.secondary) }
                else if let e = store.formError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                if let note = store.addressesNote { Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
                else if store.verified.isEmpty {
                    Text("Add and verify a destination address in the Cloudflare dashboard first. Rules can only forward to verified addresses.").font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Address, for example hello@\(store.zone.name)", text: $address).frame(minWidth: 220)
                    Picker("Forward to", selection: $destination) {
                        Text("Choose\u{2026}").tag("")
                        ForEach(store.verified) { Text($0.email).tag($0.email) }
                    }.frame(maxWidth: 260)
                    Button("Add rule") { Task { await store.create(address: address, destination: destination); if store.formError == nil { address = "" } } }
                        .disabled(!store.canWrite || store.busy || address.isEmpty || destination.isEmpty)
                }
            }.padding(12)
        }
        .navigationTitle("\(store.zone.name) email")
        .task { await store.load() }
        .confirmationDialog("Delete this rule?", isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }), presenting: store.confirm.pending) { change in
            Button("Delete rule", role: .destructive) { Task { await store.confirmChange(change) } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { Text($0.message) }
    }
}
