import SwiftUI
import CloudflareKit

struct TurnstileView: View {
    @Environment(TurnstileStore.self) private var store
    @Environment(Session.self) private var session
    @State private var creating = false
    @State private var deleting: TurnstileWidget?
    @State private var name = ""
    @State private var domains = ""
    @State private var mode = "managed"
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Turnstile widgets replace CAPTCHAs on your forms.").foregroundStyle(.secondary)
                Spacer()
                Button("New", systemImage: "plus") { name = ""; domains = ""; store.formError = nil; creating = true }.disabled(!store.canWrite)
            }.padding()
            if !store.canWrite { Label("This token can't change Turnstile. Add Turnstile Sites Edit to it in Cloudflare.", systemImage: "lock").foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8) }
            else if let e = store.formError, deleting == nil, !creating { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(.horizontal).padding(.bottom, 8) }
            Divider()
            LoadStateView(state: store.widgets, permission: "Turnstile Sites Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No Turnstile widgets", emptyMessage: "Create one, then put its site key on your page and its secret on your server.", emptySymbol: "checkmark.shield",
                          retry: { Task { await store.load() } }) { list in
                List(list) { w in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(w.name)
                            Text([w.sitekey, w.mode, w.domains?.joined(separator: ", ")].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Button("Delete\u{2026}", role: .destructive) { store.formError = nil; deleting = w }.disabled(!store.canWrite).accessibilityLabel("Delete \(w.name)")
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: session.identityEpoch) { await store.load() }
        .onChange(of: session.identityEpoch) { deleting = nil; creating = false }
        .sheet(item: $deleting) { w in
            TypedConfirmSheet(title: "Delete \(w.name)?", message: "Forms using this widget stop verifying visitors. It can't be undone. Type its name to confirm.",
                              name: w.name, buttonLabel: "Delete widget", error: store.formError,
                              onConfirm: { await store.delete(w, typedName: $0) }, onDone: { if store.formError == nil { deleting = nil } })
        }
        .sheet(isPresented: Binding(get: { creating || store.newSecret != nil }, set: { if !$0 { creating = false; store.dismissSecret() } })) {
            if let secret = store.newSecret {
                SecretSheet(secret: secret, idLabel: "Site key", secretLabel: "Secret key") { store.dismissSecret(); creating = false }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Turnstile widget").font(.headline)
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    TextField("Hostnames, for example example.com", text: $domains, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                    Picker("Mode", selection: $mode) { Text("Managed").tag("managed"); Text("Non-interactive").tag("non-interactive"); Text("Invisible").tag("invisible") }
                    if let e = store.formError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
                    HStack {
                        Spacer()
                        Button("Cancel") { store.formError = nil; creating = false }
                        Button("Create") {
                            Task { working = true; await store.create(name: name, domains: domains, mode: mode); working = false; if store.formError == nil && store.newSecret == nil { creating = false } }
                        }.disabled(working || name.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
                    }
                }.padding(20).frame(width: 420)
            }
        }
    }
}
