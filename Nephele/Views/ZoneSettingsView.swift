import SwiftUI
import CloudflareKit

struct ZoneSettingsView: View {
    @State private var store: ZoneSettingsStore
    @State private var urls = ""
    @State private var purgingAll = false

    init(zone: Zone, session: Session) { _store = State(initialValue: ZoneSettingsStore(zone: zone, session: session)) }

    private static let sslModes = [("off", "Off (not secure)"), ("flexible", "Flexible"), ("full", "Full"), ("strict", "Full (strict)")]
    private static let tlsVersions = [("1.0", "TLS 1.0"), ("1.1", "TLS 1.1"), ("1.2", "TLS 1.2"), ("1.3", "TLS 1.3")]
    private static let levels = [("essentially_off", "Essentially off"), ("low", "Low"), ("medium", "Medium"), ("high", "High"), ("under_attack", "I'm under attack")]

    var body: some View {
        LoadStateView(state: store.settings, permission: "Zone Settings Read", isEmpty: { _ in false },
                      emptyTitle: "", emptyMessage: "", emptySymbol: "gearshape", retry: { Task { await store.load() } }) { _ in
            Form {
                if !store.canChange { Section { Label("This token can't change settings. Add Zone Settings Edit to it in Cloudflare.", systemImage: "lock").foregroundStyle(.secondary) } }
                if let e = store.formError, !purgingAll, store.canChange || e != StorageCopy.editHint("Zone Settings Edit") { Section { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
                if let n = store.notice { Section { Label(n, systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
                Section("SSL/TLS") {
                    picker("Encryption mode", ZoneSettingID.ssl, Self.sslModes)
                    toggle("Always use HTTPS", ZoneSettingID.alwaysHTTPS)
                    toggle("Automatic HTTPS rewrites", ZoneSettingID.rewrites)
                    picker("Minimum TLS version", ZoneSettingID.minTLS, Self.tlsVersions)
                    toggle("TLS 1.3", ZoneSettingID.tls13, onWhen: { $0 != "off" })
                }
                Section("Security") { picker("Security level", ZoneSettingID.securityLevel, Self.levels) }
                Section("Caching") {
                    toggle("Development mode", ZoneSettingID.devMode)
                    Text("Development mode skips the cache for three hours so changes show straight away.").font(.footnote).foregroundStyle(.secondary)
                    TextField("URLs to purge, one per line", text: $urls, axis: .vertical).lineLimit(3...6)
                    HStack {
                        Button("Purge these URLs") { Task { await store.purgeFiles(urls) } }.disabled(!store.canPurge || urls.allSatisfy(\.isWhitespace))
                        Spacer()
                        Button("Purge everything\u{2026}", role: .destructive) { store.formError = nil; purgingAll = true }.disabled(!store.canPurge)
                    }
                }
            }.formStyle(.grouped)
        }
        .navigationTitle("\(store.zone.name) settings")
        .task { await store.load() }
        .confirmationDialog(store.confirm.pending.map { _ in "Change this setting?" } ?? "",
                            isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }),
                            presenting: store.confirm.pending) { change in
            Button("Change it", role: .destructive) { Task { await store.confirmChange(change) } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { Text($0.message) }
        .sheet(isPresented: $purgingAll) {
            TypedConfirmSheet(title: "Purge everything?", message: "Every cached file for this domain is dropped, so visitors hit your origin until the cache refills. Type the domain name to confirm.",
                              name: store.zone.name, buttonLabel: "Purge cache", error: store.formError,
                              onConfirm: { await store.purgeEverything(typedName: $0) }, onDone: { if store.formError == nil { purgingAll = false } })
        }
    }

    private func picker(_ title: String, _ id: String, _ options: [(String, String)]) -> some View {
        Picker(title, selection: Binding(get: { store.value(id) ?? "" }, set: { v in Task { await store.request(id, v) } })) {
            if store.value(id).map({ v in !options.contains { $0.0 == v } }) == true { Text(store.value(id) ?? "").tag(store.value(id) ?? "") }
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .disabled(!store.editable(id) || store.value(id) == nil || store.busy.contains(id))
    }

    private func toggle(_ title: String, _ id: String, onWhen: @escaping (String) -> Bool = { $0 == "on" }) -> some View {
        Toggle(title, isOn: Binding(get: { store.value(id).map(onWhen) ?? false }, set: { v in Task { await store.request(id, v ? "on" : "off") } }))
            .disabled(!store.editable(id) || store.value(id) == nil || store.busy.contains(id))
    }
}
