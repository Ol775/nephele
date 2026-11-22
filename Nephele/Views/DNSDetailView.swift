import SwiftUI
import CloudflareKit

struct DNSDetailView: View {
    @State private var store: DNSStore
    @State private var type = "A"
    @State private var name = ""
    @State private var content = ""
    @State private var priority = 10
    @State private var proxied = false
    @State private var editing: DNSRecord?
    @State private var showSettings = false

    private let session: Session
    init(zone: Zone, session: Session) {
        self.session = session
        _store = State(initialValue: DNSStore(zone: zone, session: session)) }

    var body: some View {
        VStack(spacing: 0) {
            LoadStateView(state: store.records, permission: "DNS Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No DNS records", emptyMessage: "Add the first record below.", emptySymbol: "list.bullet.rectangle",
                          retry: { Task { await store.load() } }) { records in
                Table(records) {
                    TableColumn("Type") { Text($0.type).monospaced() }.width(70)
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Content") { Text($0.content).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Proxy") { record in
                        Button { store.requestProxyToggle(record) } label: {
                            Image(systemName: record.proxied == true ? "cloud.fill" : "cloud.slash")
                        }
                        .buttonStyle(.borderless).foregroundStyle(record.proxied == true ? Color.accentColor : .secondary)
                        .help(record.proxied == true ? "Proxied. Click for DNS only." : "DNS only. Click to proxy.")
                        .accessibilityLabel(record.proxied == true ? "Proxied" : "DNS only")
                    }.width(60)
                    TableColumn("") { record in
                        HStack(spacing: 10) {
                            Button { editing = record } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).help("Edit").accessibilityLabel("Edit \(record.type) record \(record.name)")
                            Button(role: .destructive) { store.requestDelete(record) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete \(record.type) record \(record.name)")
                        }
                    }.width(70)
                }
            }
            Divider()
            addForm
        }
        .navigationTitle(store.zone.name)
        .toolbar { ToolbarItem { Button("Settings", systemImage: "gearshape") { showSettings = true } } }
        .navigationDestination(isPresented: $showSettings) { ZoneSettingsView(zone: store.zone, session: session) }
        .task { await store.load() }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { store.pending != nil }, set: { if !$0 { store.dialogDismissed() } }), presenting: store.pending) { action in
            Button(action.kind == .delete ? "Delete \(action.record.type) record" : (action.record.proxied == true ? "Switch to DNS only" : "Proxy through Cloudflare"), role: action.kind == .delete ? .destructive : nil) {
                Task { await store.confirm(action) }
            }
            Button("Cancel", role: .cancel) { store.cancel() }
        } message: { action in
            Text(message(for: action))
        }
        .sheet(item: $editing) { record in
            EditRecordSheet(record: record, store: store) { editing = nil }
        }
    }

    private var dialogTitle: String { store.pending?.kind == .proxy ? "Change proxy setting?" : "Delete DNS record?" }

    private func message(for action: PendingAction) -> String {
        let r = action.record
        switch action.kind {
        case .delete: return "This deletes the \(r.type) record \(r.name). It is live DNS and changes straight away."
        case .proxy:
            return r.proxied == true
                ? "\(r.name) will stop going through Cloudflare, which exposes the origin address. It changes straight away."
                : "\(r.name) will start going through Cloudflare. Services such as mail or SSH on this name may stop working. It changes straight away."
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: $type) { ForEach(["A", "AAAA", "CNAME", "TXT", "MX"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 90)
                TextField("Name, for example blog", text: $name).frame(minWidth: 150)
                TextField("Content", text: $content).frame(minWidth: 200)
                if type == "MX" { Stepper("Priority \(priority)", value: $priority, in: 0...65535) }
                if ["A", "AAAA", "CNAME"].contains(type) { Toggle("Proxied", isOn: $proxied).help("Off keeps this name DNS only, which is right for mail and SSH.") }
                Button("Add record") {
                    Task {
                        await store.add(DNSRecordDraft(type: type, name: name, content: content, proxied: proxied, priority: type == "MX" ? priority : nil))
                        if store.formError == nil { name = ""; content = "" }
                    }
                }
            }
            if let error = store.formError { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(12)
    }
}

private struct EditRecordSheet: View {
    let record: DNSRecord
    let store: DNSStore
    let done: () -> Void
    @State private var name: String
    @State private var content: String
    @State private var ttl: Int
    @State private var priority: Int
    @State private var proxied: Bool

    init(record: DNSRecord, store: DNSStore, done: @escaping () -> Void) {
        self.record = record; self.store = store; self.done = done
        _name = State(initialValue: record.name); _content = State(initialValue: record.content)
        _ttl = State(initialValue: record.ttl); _priority = State(initialValue: record.priority ?? 10); _proxied = State(initialValue: record.proxied ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(record.type) record").font(.headline)
            TextField("Name", text: $name)
            TextField("Content", text: $content)
            Picker("TTL", selection: $ttl) {
                Text("Auto").tag(1); Text("1 minute").tag(60); Text("5 minutes").tag(300); Text("1 hour").tag(3600); Text("1 day").tag(86400)
            }
            if record.type == "MX" { Stepper("Priority \(priority)", value: $priority, in: 0...65535) }
            if ["A", "AAAA", "CNAME"].contains(record.type) { Toggle("Proxied", isOn: $proxied) }
            if let error = store.formError { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { store.formError = nil; done() }
                Button("Save changes") {
                    Task {
                        await store.update(record, with: DNSRecordDraft(type: record.type, name: name, content: content, proxied: proxied, ttl: ttl, priority: record.type == "MX" ? priority : nil))
                        if store.formError == nil { done() }
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 440)
    }
}
