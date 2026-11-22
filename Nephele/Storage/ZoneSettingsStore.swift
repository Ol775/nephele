import Foundation
import Observation
import CloudflareKit

/// SSL/TLS, security and caching settings for one zone, plus cache purge.
@MainActor @Observable
final class ZoneSettingsStore {
    let zone: Zone
    private(set) var settings: LoadState<[String: ZoneSetting]> = .idle
    private(set) var canChange = true
    private(set) var canPurge = true
    private(set) var busy: Set<String> = []
    private(set) var notice: String?
    var formError: String?

    @ObservationIgnored let session: Session
    init(zone: Zone, session: Session) { self.zone = zone; self.session = session }

    func value(_ id: String) -> String? { settings.value?[id]?.value }
    func editable(_ id: String) -> Bool { canChange && settings.value?[id]?.editable != false }

    func load() async {
        guard let client = session.client else { return }
        let epoch = session.identityEpoch
        if settings.value == nil { settings = .loading }
        do {
            let list = try await client.zoneSettings(zoneID: zone.id)
            guard epoch == session.identityEpoch else { return }
            settings = .loaded(Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 }))
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if settings.value == nil { settings = .failed(error) }
        } catch { if settings.value == nil { settings = .failed(.transport("unknown")) } }
    }

    func set(_ id: String, _ newValue: String) async {
        formError = nil; notice = nil
        guard let client = session.client, !busy.contains(id) else { return }
        let epoch = session.identityEpoch
        busy.insert(id); defer { busy.remove(id) }
        do {
            let updated = try await client.updateZoneSetting(zoneID: zone.id, id: id, value: newValue)
            guard epoch == session.identityEpoch else { return }
            var all = settings.value ?? [:]
            all[id] = updated
            settings = .loaded(all)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { canChange = false; formError = StorageCopy.editHint("Zone Settings Edit") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }

    func purgeEverything(typedName: String) async {
        formError = nil; notice = nil
        guard typedName == zone.name else { formError = "Type \(zone.name) exactly to purge its whole cache."; return }
        await purge(.everything, done: "Purged the whole cache. It can take a few seconds to take effect.")
    }

    func purgeFiles(_ text: String) async {
        formError = nil; notice = nil
        switch PurgeURLs.parse(text) {
        case .failure(let e): formError = e.errorDescription
        case .success(let urls): await purge(.files(urls), done: "Purged \(urls.count) URL\(urls.count == 1 ? "" : "s").")
        }
    }

    private func purge(_ scope: PurgeScope, done: String) async {
        guard let client = session.client else { return }
        let epoch = session.identityEpoch
        do {
            try await client.purgeCache(zoneID: zone.id, scope)
            guard epoch == session.identityEpoch else { return }
            notice = done
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { canPurge = false; formError = StorageCopy.editHint("Cache Purge") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't purge the cache." }
    }
}
