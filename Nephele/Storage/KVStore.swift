import Foundation
import Observation
import CloudflareKit

enum KVChange: Equatable, Sendable {
    case deleteKey(String)

    func title(namespace: String) -> String { switch self { case .deleteKey(let k): "Delete key \(k)?" } }
    func message(namespace: String) -> String { switch self { case .deleteKey(let k): "The key \(k) and its value will be removed from \(namespace). This can't be undone." } }
}

@MainActor @Observable
final class KVStore {
    struct Value: Equatable { let key: String; let byteCount: Int; let isText: Bool }

    private(set) var namespaces: LoadState<[KVNamespace]> = .idle
    private(set) var selected: KVNamespace?
    private(set) var keys: [KVKey] = []
    private(set) var keysState: LoadState<Void> = .idle
    private(set) var nextCursor: String?
    private(set) var value: LoadState<Value> = .idle
    var prefix = ""
    var draft = ""
    private(set) var loadedText: String?
    private(set) var canWrite = true
    var formError: String?
    let confirm = ConfirmGate<KVChange>()

    @ObservationIgnored private let session: Session

    init(session: Session) { self.session = session }

    var hasUnsavedChanges: Bool { loadedText.map { $0 != draft } ?? false }

    func reset() {
        namespaces = .idle; selected = nil; keys = []; keysState = .idle; nextCursor = nil
        value = .idle; prefix = ""; draft = ""; loadedText = nil; canWrite = true; formError = nil; confirm.cancel()
    }

    private var account: String? { session.selectedAccountID }

    func load() async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if namespaces.value == nil { namespaces = .loading }
        do {
            let list = try await client.kvNamespaces(accountID: account).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard epoch == session.identityEpoch else { return }
            namespaces = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if namespaces.value == nil { namespaces = .failed(error) }
        } catch { if namespaces.value == nil { namespaces = .failed(.transport("unknown")) } }
    }

    func select(_ namespace: KVNamespace?) async {
        selected = namespace
        keys = []; nextCursor = nil; value = .idle; draft = ""; loadedText = nil; prefix = ""; keysState = .idle
        if namespace != nil { await loadKeys(reset: true) }
    }

    func loadKeys(reset: Bool) async {
        guard let client = session.client, let account, let ns = selected else { return }
        let epoch = session.identityEpoch
        if reset { keys = []; nextCursor = nil }
        keysState = .loading
        do {
            let page = try await client.kvKeys(accountID: account, namespace: ns.id, prefix: prefix, cursor: reset ? nil : nextCursor)
            guard epoch == session.identityEpoch, selected == ns else { return }
            let known = Set(keys.map(\.name))
            keys += page.keys.filter { !known.contains($0.name) }
            nextCursor = page.nextCursor
            keysState = .loaded(())
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            keysState = .failed(error)
        } catch { keysState = .failed(.transport("unknown")) }
    }

    func loadMore() async { if nextCursor != nil { await loadKeys(reset: false) } }

    func open(_ key: KVKey) async {
        guard let client = session.client, let account, let ns = selected else { return }
        value = .loading
        do {
            let data = try await client.kvValue(accountID: account, namespace: ns.id, key: key.name)
            let text = String(data: data, encoding: .utf8)
            value = .loaded(Value(key: key.name, byteCount: data.count, isText: text != nil))
            loadedText = text
            draft = text ?? ""
        } catch let error as CloudflareError {
            session.handle(error)
            value = .failed(error)
        } catch { value = .failed(.transport("unknown")) }
    }

    func saveValue() async {
        guard case .loaded(let v) = value, v.isText, let ns = selected else { return }
        let text = draft
        await write { client, account in
            try await client.putKVValue(accountID: account, namespace: ns.id, key: v.key, value: Data(text.utf8))
            self.loadedText = text
        }
    }

    /// Adds a key with an empty-or-given text value.
    func addKey(_ name: String, value text: String) async {
        formError = nil
        guard !name.isEmpty, name.utf8.count <= 512 else { formError = "A key name is 1 to 512 bytes."; return }
        guard let ns = selected else { return }
        await write { client, account in
            try await client.putKVValue(accountID: account, namespace: ns.id, key: name, value: Data(text.utf8))
            self.keys = (self.keys.filter { $0.name != name } + [KVKey(name: name)]).sorted { $0.name < $1.name }
        }
    }

    func createNamespace(_ title: String) async {
        formError = nil
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { formError = "Enter a name for the namespace."; return }
        await write { client, account in
            let ns = try await client.createKVNamespace(accountID: account, title: title)
            self.namespaces = .loaded(((self.namespaces.value ?? []) + [ns]).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    func deleteNamespace(_ ns: KVNamespace, typedName: String) async {
        formError = nil
        guard typedName == ns.title else { formError = "Type \(ns.title) exactly to delete it."; return }
        await write { client, account in
            try await client.deleteKVNamespace(accountID: account, namespace: ns.id)
            self.namespaces = .loaded((self.namespaces.value ?? []).filter { $0.id != ns.id })
            if self.selected == ns { self.selected = nil; self.keys = []; self.value = .idle }
        }
    }

    func requestDelete(_ key: KVKey) { formError = nil; confirm.request(.deleteKey(key.name)) }

    func confirmChange(_ change: KVChange) async {
        guard confirm.take(change), let ns = selected else { return }
        switch change {
        case .deleteKey(let name):
            await write { client, account in
                try await client.deleteKVKey(accountID: account, namespace: ns.id, key: name)
                self.keys.removeAll { $0.name == name }
                if case .loaded(let v) = self.value, v.key == name { self.value = .idle; self.draft = ""; self.loadedText = nil }
            }
        }
    }

    private func write(_ body: (CFClient, String) async throws -> Void) async {
        guard let client = session.client, let account else { return }
        do { try await body(client, account) }
        catch let error as CloudflareError {
            if case .permissionDenied = error { canWrite = false; formError = StorageCopy.editHint("Workers KV Storage Edit") }
            else { session.handle(error); formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }
}
