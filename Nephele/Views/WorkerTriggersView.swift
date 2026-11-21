import SwiftUI
import CloudflareKit

struct WorkerTriggersView: View {
    let store: WorkerStore
    @Environment(DomainsStore.self) private var domains
    @State private var cron = ""
    @State private var pattern = ""
    @State private var routeZoneID = ""
    @State private var hostname = ""
    @State private var domainZoneID = ""

    private var zones: [Zone] { domains.zones.value ?? [] }
    private func zone(_ id: String) -> Zone? { zones.first { $0.id == id } ?? zones.first }

    var body: some View {
        Form {
            if !store.canWrite { Section { Label("Needs a token with Workers Scripts Edit", systemImage: "lock").foregroundStyle(.secondary) } }
            if let error = store.formError { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
            LoadStateView(state: store.triggers, permission: "Workers Scripts Read", retry: { Task { await reload() } }) { t in
                if !t.unreadableZones.isEmpty {
                    Section { Label("Couldn't read routes for \(t.unreadableZones.joined(separator: ", ")).", systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
                }
                Section("Cron triggers") {
                    ForEach(t.crons, id: \.self) { c in
                        LabeledContent { removeButton("Remove cron trigger \(c)") { store.requestChange(.removeCron(c)) } } label: { Text(c).monospaced() }
                    }
                    if t.crons.isEmpty { Text("No schedules.").foregroundStyle(.secondary) }
                    HStack {
                        TextField("Cron", text: $cron, prompt: Text("*/30 * * * *")).monospaced()
                        Button("Add") { Task { await store.addCron(cron); if store.formError == nil { cron = "" } } }
                            .disabled(!store.canWrite || cron.isEmpty)
                    }
                }
                Section("Routes") {
                    ForEach(t.routes) { r in
                        LabeledContent { removeButton("Remove route \(r.route.pattern)") { store.requestChange(.removeRoute(id: r.route.id, pattern: r.route.pattern, zoneID: r.zone.id)) } } label: {
                            VStack(alignment: .leading) { Text(r.route.pattern).monospaced(); Text(r.zone.name).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    if t.routes.isEmpty { Text("No routes.").foregroundStyle(.secondary) }
                    HStack {
                        Picker("Domain", selection: $routeZoneID) { ForEach(zones) { Text($0.name).tag($0.id) } }.labelsHidden().frame(maxWidth: 180)
                        TextField("Pattern", text: $pattern, prompt: Text("api.example.dev/*")).monospaced()
                        Button("Add") { if let z = zone(routeZoneID) { Task { await store.addRoute(pattern: pattern, zone: z); if store.formError == nil { pattern = "" } } } }
                            .disabled(!store.canWrite || pattern.isEmpty || zones.isEmpty)
                    }
                }
                Section("Custom domains") {
                    ForEach(t.domains) { d in
                        LabeledContent { removeButton("Remove custom domain \(d.hostname)") { store.requestChange(.detachDomain(id: d.id, hostname: d.hostname)) } } label: { Text(d.hostname) }
                    }
                    if t.domains.isEmpty { Text("No custom domains.").foregroundStyle(.secondary) }
                    HStack {
                        Picker("Domain", selection: $domainZoneID) { ForEach(zones) { Text($0.name).tag($0.id) } }.labelsHidden().frame(maxWidth: 180)
                        TextField("Hostname", text: $hostname, prompt: Text("api.example.dev"))
                        Button("Attach") { if let z = zone(domainZoneID) { Task { await store.attachDomain(hostname: hostname, zone: z); if store.formError == nil { hostname = "" } } } }
                            .disabled(!store.canWrite || hostname.isEmpty || zones.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await domains.load(); routeZoneID = zones.first?.id ?? ""; domainZoneID = routeZoneID; await reload() }
        .confirmationDialog(store.confirm.pending?.title(worker: store.script.id) ?? "",
                            isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }),
                            presenting: store.confirm.pending) { change in
            Button(change.confirmLabel, role: change.isDestructive ? .destructive : nil) { Task { await store.confirmChange(change) } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { change in Text(change.message(worker: store.script.id)) }
    }

    private func reload() async { await store.loadTriggers(zones: zones) }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Image(systemName: "trash") }
            .buttonStyle(.borderless).disabled(!store.canWrite).accessibilityLabel(label)
    }
}
