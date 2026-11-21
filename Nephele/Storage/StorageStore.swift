import Foundation
import Observation
import CloudflareKit

/// Groups the three storage products so the app injects one object and resets them together.
@MainActor @Observable
final class StorageStore {
    let kv: KVStore
    let d1: D1Store
    let r2: R2Store

    init(session: Session) {
        kv = KVStore(session: session)
        d1 = D1Store(session: session)
        r2 = R2Store(session: session)
    }

    func reset() { kv.reset(); d1.reset(); r2.reset() }
}

/// Shared by the three product stores: the write-denied hint and a typed-name check.
enum StorageCopy {
    static func editHint(_ permission: String) -> String { "This token can't change this. Add \(permission) to it in Cloudflare, then try again." }
}
