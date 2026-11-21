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
                case .d1: ContentUnavailableView("D1", systemImage: "hammer", description: Text("Coming next."))
                case .r2: ContentUnavailableView("R2", systemImage: "hammer", description: Text("Coming next."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct KVView: View {
    @Environment(StorageStore.self) private var storage
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
                    Button("Save") { Task { await kv.saveValue() } }.disabled(!kv.hasUnsavedChanges || !kv.canWrite || !v.isText)
                }.padding(8)
                Divider()
                if v.isText {
                    TextEditor(text: $kv.draft).font(.system(size: theme.fontSize, design: .monospaced)).padding(4)
                } else {
                    ContentUnavailableView("Binary value", systemImage: "doc", description: Text("\(v.byteCount) bytes. Nephele only edits text values."))
                }
            }
            .overlay { if case .idle = kv.value { ContentUnavailableView("Pick a key", systemImage: "doc.text", description: Text("Its value appears here.")) } }
        }
    }
}

