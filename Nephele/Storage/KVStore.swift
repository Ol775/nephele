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
    struct Value: Equatable { let key: String; let namespaceID: String; let byteCount: Int; let isText: Bool; let expiration: Double?; let hasMetadata: Bool }

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

    @ObservationIgnored let session: Session

    init(session: Session) { self.session = session }

    /// Why the open value can't be saved from here, or nil when it can.
    var editBlockedReason: String? {
        guard case .loaded(let v) = value else { return nil }
        if !v.isText { return "Nephele only edits text values." }
        if v.hasMetadata { return "This key has metadata, and saving here would erase it, so it's read-only." }
        return nil
    }

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
        let epoch = session.identityEpoch
        value = .loading
        do {
            let data = try await client.kvValue(accountID: account, namespace: ns.id, key: key.name)
            // The user may have picked another namespace or account while this loaded.
            guard epoch == session.identityEpoch, selected == ns else { return }
            let text = String(data: data, encoding: .utf8)
            value = .loaded(Value(key: key.name, namespaceID: ns.id, byteCount: data.count, isText: text != nil, expiration: key.expiration, hasMetadata: key.metadata != nil))
            loadedText = text
            draft = text ?? ""
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch, selected == ns else { return }
            session.handle(error)
            value = .failed(error)
        } catch { value = .failed(.transport("unknown")) }
    }

    func saveValue() async {
        guard case .loaded(let v) = value, editBlockedReason == nil, let ns = selected, v.namespaceID == ns.id else { return }
        let text = draft
        await write { client, account, isCurrent in
            try await client.putKVValue(accountID: account, namespace: v.namespaceID, key: v.key, value: Data(text.utf8), expiration: v.expiration)
            if isCurrent(), case .loaded(let now) = self.value, now == v { self.loadedText = text }
        }
    }

    /// Adds a key with the given text value. It refuses a name that already exists rather than overwrite it.
    func addKey(_ name: String, value text: String) async {
        formError = nil
        guard !name.isEmpty, name.utf8.count <= 512, name != ".", name != ".." else { formError = "A key name is 1 to 512 bytes and can't be . or .."; return }
        guard let ns = selected else { return }
        await write { client, account, isCurrent in
            do {
                _ = try await client.kvValue(accountID: account, namespace: ns.id, key: name)
                throw StoreMessage(text: "That key already exists. Open it from the list to edit it.")
            } catch let error as CloudflareError where error == .transport("HTTP 404") {}
            try await client.putKVValue(accountID: account, namespace: ns.id, key: name, value: Data(text.utf8))
            guard isCurrent(), self.selected == ns else { return }
            self.keys = (self.keys + [KVKey(name: name)]).sorted { $0.name < $1.name }
        }
    }

    func createNamespace(_ title: String) async {
        formError = nil
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { formError = "Enter a name for the namespace."; return }
        await write { client, account, isCurrent in
            let ns = try await client.createKVNamespace(accountID: account, title: title)
            guard isCurrent() else { return }
            self.namespaces = .loaded(((self.namespaces.value ?? []) + [ns]).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    func deleteNamespace(_ ns: KVNamespace, typedName: String) async {
        formError = nil
        guard typedName == ns.title else { formError = "Type \(ns.title) exactly to delete it."; return }
        await write { client, account, isCurrent in
            try await client.deleteKVNamespace(accountID: account, namespace: ns.id)
            guard isCurrent() else { return }
            self.namespaces = .loaded((self.namespaces.value ?? []).filter { $0.id != ns.id })
            if self.selected == ns { self.selected = nil; self.keys = []; self.value = .idle }
        }
    }

    func requestDelete(_ key: KVKey) { formError = nil; confirm.request(.deleteKey(key.name)) }

    func confirmChange(_ change: KVChange) async {
        guard confirm.take(change), let ns = selected else { return }
        switch change {
        case .deleteKey(let name):
            await write { client, account, isCurrent in
                try await client.deleteKVKey(accountID: account, namespace: ns.id, key: name)
                guard isCurrent() else { return }
                self.keys.removeAll { $0.name == name }
                if case .loaded(let v) = self.value, v.key == name { self.value = .idle; self.draft = ""; self.loadedText = nil }
            }
        }
    }

    struct StoreMessage: Error { let text: String }

    /// Runs one write. `isCurrent` turns false if the account changed meanwhile, so late results aren't applied.
    private func write(_ body: (CFClient, String, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do { try await body(client, account, { [session] in epoch == session.identityEpoch }) }
        catch let message as StoreMessage { formError = message.text }
        catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { canWrite = false; formError = StorageCopy.editHint("Workers KV Storage Edit") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }
}
