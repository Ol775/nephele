import SwiftUI
import CloudflareKit

enum StorageTab: String, CaseIterable, Identifiable {
    case kv = "KV", d1 = "D1", r2 = "R2"
    var id: String { rawValue }
}

struct StorageView: View {
    @State private var tab = StorageTab.kv

    var body: some View {
        VStack(spacing: 0) {
            Picker("Product", selection: $tab) { ForEach(StorageTab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding()
            Divider()
            Group {
                switch tab {
                case .kv: KVView()
                case .d1: D1View()
                case .r2: R2View()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct KVView: View {
    @Environment(StorageStore.self) private var storage
    @Environment(Session.self) private var session
    @Environment(\.nepheleTheme) private var theme
    @State private var creating = false
    @State private var newTitle = ""
    @State private var deleting: KVNamespace?
    @State private var newKey = ""

    private var kv: KVStore { storage.kv }

    var body: some View {
        @Bindable var kv = storage.kv
        HSplitView {
            namespaces.frame(minWidth: 180, idealWidth: 210, maxWidth: 280)
            keys.frame(minWidth: 220, idealWidth: 280)
            valuePane.frame(minWidth: 280)
        }
        .task { await kv.load() }
        .onChange(of: session.identityEpoch) { deleting = nil }
        .sheet(item: $deleting) { ns in
            TypedConfirmSheet(title: "Delete \(ns.title)?", message: "This deletes the namespace and every key in it. It can't be undone. Type its name to confirm.",
                              name: ns.title, buttonLabel: "Delete namespace", error: kv.formError,
                              onConfirm: { await kv.deleteNamespace(ns, typedName: $0) }, onDone: { if kv.formError == nil { deleting = nil } })
        }
        .alert("New namespace", isPresented: $creating) {
            TextField("Name", text: $newTitle)
            Button("Create") { Task { await kv.createNamespace(newTitle); newTitle = "" } }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .confirmationDialog(kv.confirm.pending?.title(namespace: kv.selected?.title ?? "") ?? "",
                            isPresented: Binding(get: { kv.confirm.pending != nil }, set: { if !$0 { kv.confirm.dialogDismissed() } }),
                            presenting: kv.confirm.pending) { change in
            Button("Delete key", role: .destructive) { Task { await kv.confirmChange(change) } }
            Button("Cancel", role: .cancel) { kv.confirm.cancel() }
        } message: { change in Text(change.message(namespace: kv.selected?.title ?? "")) }
    }

    private var namespaces: some View {
        VStack(spacing: 0) {
            LoadStateView(state: kv.namespaces, permission: "Workers KV Storage Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No namespaces", emptyMessage: "Create one to start storing keys.", emptySymbol: "key",
                          retry: { Task { await kv.load() } }) { list in
                List(list, selection: Binding(get: { kv.selected?.id }, set: { id in Task { await kv.select(list.first { $0.id == id }) } })) { ns in
                    Text(ns.title).tag(ns.id)
                        .contextMenu { Button("Delete\u{2026}", role: .destructive) { deleting = ns }.disabled(!kv.canWrite) }
                }
            }
            Divider()
            HStack {
                Button("New", systemImage: "plus") { creating = true }.disabled(!kv.canWrite)
                if let ns = kv.selected { Button("Delete", systemImage: "trash") { deleting = ns }.disabled(!kv.canWrite) }
                Spacer()
            }.padding(8)
        }
    }

    private var keys: some View {
        @Bindable var kv = storage.kv
        return VStack(spacing: 0) {
            if kv.selected == nil {
                ContentUnavailableView("Pick a namespace", systemImage: "key", description: Text("Its keys appear here."))
            } else {
                TextField("Filter by prefix", text: $kv.prefix).textFieldStyle(.roundedBorder).padding(8)
                    .onSubmit { Task { await kv.loadKeys(reset: true) } }
                LoadStateView(state: kv.keysState, permission: "Workers KV Storage Read", retry: { Task { await kv.loadKeys(reset: true) } }) { _ in
                    List(kv.keys, selection: Binding(get: { Optional<String>.none }, set: { name in if let k = kv.keys.first(where: { $0.name == name }) { Task { await kv.open(k) } } })) { key in
                        HStack {
                            Text(key.name).monospaced().lineLimit(1).tag(key.name)
                            Spacer()
                            Button { kv.requestDelete(key) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).disabled(!kv.canWrite).accessibilityLabel("Delete key \(key.name)")
                        }
                    }
                    if kv.nextCursor != nil { Button("Load more") { Task { await kv.loadMore() } }.padding(8) }
                }
                Divider()
                HStack {
                    TextField("New key", text: $newKey).textFieldStyle(.roundedBorder)
                    Button("Add") { Task { await kv.addKey(newKey, value: ""); if kv.formError == nil { newKey = "" } } }
                        .disabled(!kv.canWrite || newKey.isEmpty)
                }.padding(8)
            }
        }
    }

    private var valuePane: some View {
        @Bindable var kv = storage.kv
        return VStack(spacing: 0) {
            if !kv.canWrite { Label("Needs a token with Workers KV Storage Edit", systemImage: "lock").foregroundStyle(.secondary).padding(8) }
            if let error = kv.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(8) }
            LoadStateView(state: kv.value, permission: "Workers KV Storage Read") { v in
                HStack {
                    Text(v.key).monospaced().lineLimit(1)
                    Spacer()
                    Button("Save") { Task { await kv.saveValue() } }.disabled(!kv.hasUnsavedChanges || !kv.canWrite || kv.editBlockedReason != nil)
                }.padding(8)
                if let reason = kv.editBlockedReason { Label(reason, systemImage: "lock").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 8) }
                Divider()
                if v.isText {
                    TextEditor(text: $kv.draft).disabled(kv.editBlockedReason != nil).font(.system(size: theme.fontSize, design: .monospaced)).padding(4)
                } else {
                    ContentUnavailableView("Binary value", systemImage: "doc", description: Text("\(v.byteCount) bytes. Nephele only edits text values."))
                }
            }
            .overlay { if case .idle = kv.value { ContentUnavailableView("Pick a key", systemImage: "doc.text", description: Text("Its value appears here.")) } }
        }
    }
}


struct D1View: View {
    @Environment(StorageStore.self) private var storage
    @Environment(Session.self) private var session
    @Environment(\.nepheleTheme) private var theme
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: D1Database?

    var body: some View {
        @Bindable var d1 = storage.d1
        HSplitView {
            VStack(spacing: 0) {
                LoadStateView(state: d1.databases, permission: "D1 Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No databases", emptyMessage: "Create one to start running SQL.", emptySymbol: "cylinder.split.1x2",
                              retry: { Task { await d1.load() } }) { list in
                    List(list, selection: Binding(get: { d1.selected?.id }, set: { id in Task { await d1.select(list.first { $0.id == id }) } })) { db in
                        Text(db.name).tag(db.id).contextMenu { Button("Delete\u{2026}", role: .destructive) { deleting = db }.disabled(!d1.canWrite) }
                    }
                }
                if !d1.tables.isEmpty {
                    Divider()
                    List(d1.tables, id: \.self) { t in
                        Text(t).monospaced().onTapGesture { d1.sql = "SELECT * FROM \(D1SQL.quoteIdentifier(t)) LIMIT 100;" }
                    }.frame(maxHeight: 180)
                }
                Divider()
                HStack {
                    Button("New", systemImage: "plus") { creating = true }.disabled(!d1.canWrite)
                    if let db = d1.selected { Button("Delete", systemImage: "trash") { deleting = db }.disabled(!d1.canWrite) }
                    Spacer()
                }.padding(8)
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            console
        }
        .task { await d1.load() }
        .onChange(of: session.identityEpoch) { deleting = nil }
        .sheet(item: $deleting) { db in
            TypedConfirmSheet(title: "Delete \(db.name)?", message: "This deletes the database and all its data. It can't be undone. Type its name to confirm.",
                              name: db.name, buttonLabel: "Delete database", error: d1.formError,
                              onConfirm: { await d1.delete(db, typedName: $0) }, onDone: { if d1.formError == nil { deleting = nil } })
        }
        .alert("New database", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await d1.create(newName); newName = "" } }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .confirmationDialog(d1.confirm.pending?.title(database: d1.selected?.name ?? "") ?? "",
                            isPresented: Binding(get: { d1.confirm.pending != nil }, set: { if !$0 { d1.confirm.dialogDismissed() } }),
                            presenting: d1.confirm.pending) { w in
            Button("Run statement", role: .destructive) { Task { await d1.confirmWrite(w) } }
            Button("Cancel", role: .cancel) { d1.confirm.cancel() }
        } message: { w in Text(w.message(database: d1.selected?.name ?? "")) }
    }

    private var console: some View {
        @Bindable var d1 = storage.d1
        return VStack(spacing: 0) {
            if d1.selected == nil {
                ContentUnavailableView("Pick a database", systemImage: "cylinder.split.1x2", description: Text("Run SQL against it here."))
            } else {
                if !d1.canWrite { Label("Needs a token with D1 Edit to change data", systemImage: "lock").foregroundStyle(.secondary).padding(8) }
                if let error = d1.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(8) }
                TextEditor(text: $d1.sql).font(.system(size: theme.fontSize, design: .monospaced)).frame(height: 120).padding(4)
                    .accessibilityLabel("SQL")
                HStack {
                    Text("Reads run straight away. Anything that changes data asks first.").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Run") { Task { await d1.run() } }.keyboardShortcut(.return, modifiers: .command).disabled(d1.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(8)
                Divider()
                LoadStateView(state: d1.results, permission: "D1 Read") { results in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, r in ResultGrid(result: r) }
                        }.padding(8)
                    }
                }
                .overlay { if case .idle = d1.results { Text("Results appear here.").foregroundStyle(.secondary) } }
            }
        }
    }
}

struct ResultGrid: View {
    let result: D1Result
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(result.rows.count) rows \u{00B7} \(result.rowsRead) read \u{00B7} \(result.rowsWritten) written \u{00B7} \(String(format: "%.1f", result.duration * 1000)) ms")
                .font(.footnote).foregroundStyle(.secondary)
            if !result.columns.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { ForEach(Array(result.columns.enumerated()), id: \.offset) { _, c in Text(c).fontWeight(.semibold) } }
                    Divider()
                    ForEach(Array(result.rows.prefix(500).enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(cell).monospaced().lineLimit(2) } }
                    }
                }
                if result.rows.count > 500 { Text("Showing the first 500 rows.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

struct R2View: View {
    @Environment(StorageStore.self) private var storage
    @Environment(Session.self) private var session
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: R2Bucket?

    var body: some View {
        @Bindable var r2 = storage.r2
        HSplitView {
            VStack(spacing: 0) {
                LoadStateView(state: r2.buckets, permission: "Workers R2 Storage Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No buckets", emptyMessage: "Create one to start storing objects.", emptySymbol: "shippingbox",
                              retry: { Task { await r2.load() } }) { list in
                    List(list, selection: Binding(get: { r2.selected?.id }, set: { id in Task { await r2.select(list.first { $0.id == id }) } })) { b in
                        VStack(alignment: .leading) { Text(b.name); if let l = b.location { Text(l).font(.footnote).foregroundStyle(.secondary) } }
                            .tag(b.id).contextMenu { Button("Delete\u{2026}", role: .destructive) { deleting = b }.disabled(!r2.canWrite) }
                    }
                }
                Divider()
                HStack {
                    Button("New", systemImage: "plus") { creating = true }.disabled(!r2.canWrite)
                    if let b = r2.selected { Button("Delete", systemImage: "trash") { deleting = b }.disabled(!r2.canWrite) }
                    Spacer()
                }.padding(8)
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            objects
        }
        .task { await r2.load() }
        .onChange(of: session.identityEpoch) { deleting = nil }
        .sheet(item: $deleting) { b in
            TypedConfirmSheet(title: "Delete \(b.name)?", message: "A bucket has to be empty before it can be deleted. This can't be undone. Type its name to confirm.",
                              name: b.name, buttonLabel: "Delete bucket", error: r2.formError,
                              onConfirm: { await r2.delete(b, typedName: $0) }, onDone: { if r2.formError == nil { deleting = nil } })
        }
        .alert("New bucket", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await r2.create(newName); newName = "" } }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .confirmationDialog(r2.confirm.pending?.title(bucket: r2.selected?.name ?? "") ?? "",
                            isPresented: Binding(get: { r2.confirm.pending != nil }, set: { if !$0 { r2.confirm.dialogDismissed() } }),
                            presenting: r2.confirm.pending) { change in
            Button("Delete object", role: .destructive) { Task { await r2.confirmChange(change) } }
            Button("Cancel", role: .cancel) { r2.confirm.cancel() }
        } message: { change in Text(change.message(bucket: r2.selected?.name ?? "")) }
    }

    private var objects: some View {
        @Bindable var r2 = storage.r2
        return VStack(spacing: 0) {
            if r2.selected == nil {
                ContentUnavailableView("Pick a bucket", systemImage: "shippingbox", description: Text("Its objects appear here."))
            } else {
                if !r2.canWrite { Label("Needs a token with Workers R2 Storage Edit", systemImage: "lock").foregroundStyle(.secondary).padding(8) }
                if let error = r2.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(8) }
                TextField("Filter by prefix", text: $r2.prefix).textFieldStyle(.roundedBorder).padding(8)
                    .onSubmit { Task { await r2.loadObjects(reset: true) } }
                LoadStateView(state: r2.objectsState, permission: "Workers R2 Storage Read", retry: { Task { await r2.loadObjects(reset: true) } }) { _ in
                    List(r2.objects) { o in
                        HStack {
                            Text(o.key).monospaced().lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let size = o.size { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).foregroundStyle(.secondary) }
                            Button { r2.requestDelete(o) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).disabled(!r2.canWrite).accessibilityLabel("Delete \(o.key)")
                        }
                    }
                    if r2.nextCursor != nil { Button("Load more") { Task { await r2.loadMore() } }.padding(8) }
                }
                Text("Uploading and downloading objects isn't built yet.").font(.footnote).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}
