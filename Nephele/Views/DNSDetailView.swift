import SwiftUI
import CloudflareKit

struct DNSDetailView: View {
    @State private var store: DNSStore
    @State private var type = "A"
    @State private var name = ""
    @State private var content = ""
    @State private var priority = 10

    init(zone: Zone, session: Session) { _store = State(initialValue: DNSStore(zone: zone, session: session)) }

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
                        Button { Task { await store.toggleProxy(record) } } label: {
                            Image(systemName: record.proxied == true ? "cloud.fill" : "cloud.slash")
                        }
                        .buttonStyle(.borderless).foregroundStyle(record.proxied == true ? Color.accentColor : .secondary)
                        .help(record.proxied == true ? "Proxied. Click for DNS only." : "DNS only. Click to proxy.")
                        .accessibilityLabel(record.proxied == true ? "Proxied" : "DNS only")
                    }.width(60)
                    TableColumn("") { record in
                        Button(role: .destructive) { store.requestDelete(record) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("Delete \(record.type) record \(record.name)")
                    }.width(40)
                }
            }
            Divider()
            addForm
        }
        .navigationTitle(store.zone.name)
        .task { await store.load() }
        .confirmationDialog("Delete DNS record?", isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.cancelDelete() } }), presenting: store.pendingDelete) { record in
            Button("Delete \(record.type) record", role: .destructive) { Task { await store.confirmDelete() } }
        } message: { record in
            Text("This deletes the \(record.type) record \(record.name). It is live DNS and changes straight away.")
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: $type) { ForEach(["A", "AAAA", "CNAME", "TXT", "MX"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 90)
                TextField("Name, for example blog", text: $name).frame(minWidth: 150)
                TextField("Content", text: $content).frame(minWidth: 200)
                if type == "MX" { Stepper("Priority \(priority)", value: $priority, in: 0...65535) }
                Button("Add record") {
                    Task {
                        await store.add(DNSRecordDraft(type: type, name: name, content: content, proxied: true, priority: type == "MX" ? priority : nil))
                        if store.formError == nil { name = ""; content = "" }
                    }
                }
            }
            if let error = store.formError { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(12)
    }
}
