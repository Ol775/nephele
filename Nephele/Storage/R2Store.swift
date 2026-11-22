import Foundation
import Observation
import CloudflareKit

enum R2Change: Equatable, Sendable {
    case deleteObject(String)
    func title(bucket: String) -> String { switch self { case .deleteObject(let k): "Delete \(k)?" } }
    func message(bucket: String) -> String { switch self { case .deleteObject(let k): "The object \(k) will be removed from \(bucket). This can't be undone." } }
}

@MainActor @Observable
final class R2Store {
    private(set) var buckets: LoadState<[R2Bucket]> = .idle
    private(set) var selected: R2Bucket?
    private(set) var objects: [R2Object] = []
    private(set) var objectsState: LoadState<Void> = .idle
    private(set) var nextCursor: String?
    var prefix = ""
    private(set) var canWrite = true
    var formError: String?
    let confirm = ConfirmGate<R2Change>()

    @ObservationIgnored let session: Session

    init(session: Session) { self.session = session }

    func reset() {
        buckets = .idle; selected = nil; objects = []; objectsState = .idle; nextCursor = nil; prefix = ""; canWrite = true; formError = nil; confirm.cancel()
    }

    private var account: String? { session.selectedAccountID }

    func load() async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if buckets.value == nil { buckets = .loading }
        do {
            let list = try await client.r2Buckets(accountID: account).sorted { $0.name < $1.name }
            guard epoch == session.identityEpoch else { return }
            buckets = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if buckets.value == nil { buckets = .failed(error) }
        } catch { if buckets.value == nil { buckets = .failed(.transport("unknown")) } }
    }

    func select(_ bucket: R2Bucket?) async {
        selected = bucket; objects = []; nextCursor = nil; prefix = ""; objectsState = .idle
        if bucket != nil { await loadObjects(reset: true) }
    }

    func loadObjects(reset: Bool) async {
        guard let client = session.client, let account, let bucket = selected else { return }
        let epoch = session.identityEpoch
        if reset { objects = []; nextCursor = nil }
        objectsState = .loading
        do {
            let page = try await client.r2Objects(accountID: account, bucket: bucket.name, prefix: prefix, cursor: reset ? nil : nextCursor)
            guard epoch == session.identityEpoch, selected == bucket else { return }
            let known = Set(objects.map(\.key))
            objects += page.objects.filter { !known.contains($0.key) }
            nextCursor = page.nextCursor
            objectsState = .loaded(())
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            objectsState = .failed(error)
        } catch { objectsState = .failed(.transport("unknown")) }
    }

    func loadMore() async { if nextCursor != nil { await loadObjects(reset: false) } }

    func create(_ name: String) async {
        formError = nil
        let name = name.trimmingCharacters(in: .whitespaces)
        guard validBucketName(name) else { formError = "Use 3 to 63 lowercase letters, digits or hyphens, and don't start or end with a hyphen."; return }
        await write { client, account, isCurrent in
            let b = try await client.createR2Bucket(accountID: account, name: name)
            guard isCurrent() else { return }
            self.buckets = .loaded(((self.buckets.value ?? []) + [b]).sorted { $0.name < $1.name })
        }
    }

    func delete(_ bucket: R2Bucket, typedName: String) async {
        formError = nil
        guard typedName == bucket.name else { formError = "Type \(bucket.name) exactly to delete it."; return }
        await write { client, account, isCurrent in
            try await client.deleteR2Bucket(accountID: account, bucket: bucket.name)
            guard isCurrent() else { return }
            self.buckets = .loaded((self.buckets.value ?? []).filter { $0.name != bucket.name })
            if self.selected == bucket { self.selected = nil; self.objects = [] }
        }
    }

    func requestDelete(_ object: R2Object) { formError = nil; confirm.request(.deleteObject(object.key)) }

    func confirmChange(_ change: R2Change) async {
        guard confirm.take(change), let bucket = selected else { return }
        switch change {
        case .deleteObject(let key):
            await write { client, account, isCurrent in
                try await client.deleteR2Object(accountID: account, bucket: bucket.name, key: key)
                guard isCurrent() else { return }
                self.objects.removeAll { $0.key == key }
            }
        }
    }

    /// Runs one write. `isCurrent` turns false if the account changed meanwhile, so late results aren't applied.
    private func write(_ body: (CFClient, String, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do { try await body(client, account, { [session] in epoch == session.identityEpoch }) }
        catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { canWrite = false; formError = StorageCopy.editHint("Workers R2 Storage Edit") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }
}
