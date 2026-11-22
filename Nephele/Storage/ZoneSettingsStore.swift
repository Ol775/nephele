import Foundation
import Observation
import CloudflareKit

/// A setting change that can take a site down, so it is confirmed first.
struct ZoneChange: Equatable, Sendable {
    let id: String, value: String
    static func isRisky(_ id: String, _ value: String) -> Bool {
        switch id {
        case ZoneSettingID.ssl: ["off", "flexible", "strict"].contains(value)
        case ZoneSettingID.securityLevel: value == "under_attack"
        case ZoneSettingID.minTLS: value == "1.3"
        default: false
        }
    }
    var message: String {
        switch (id, value) {
        case (ZoneSettingID.ssl, "flexible"): "If your origin already redirects HTTP to HTTPS, visitors get a redirect loop and the site stops loading."
        case (ZoneSettingID.ssl, "strict"): "If your origin's certificate is self-signed or expired, visitors get a 526 error straight away."
        case (ZoneSettingID.ssl, _): "HTTPS stops working for this domain. With Always use HTTPS on, visitors are sent to a page that fails."
        case (ZoneSettingID.securityLevel, _): "Every visitor gets a JavaScript challenge, which breaks API clients, webhooks and monitors."
        default: "Older browsers and tools that don't support TLS 1.3 can no longer connect."
        }
    }
}

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
    let confirm = ConfirmGate<ZoneChange>()

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
            if settings.value == nil { settings = .failed(error) } else { formError = error.errorDescription }
        } catch { if settings.value == nil { settings = .failed(.transport("unknown")) } else { formError = "Couldn't refresh the settings." } }
    }

    /// Asks first when the change could break the site.
    func request(_ id: String, _ value: String) async {
        if ZoneChange.isRisky(id, value) { formError = nil; notice = nil; confirm.request(ZoneChange(id: id, value: value)) }
        else { await set(id, value) }
    }

    func confirmChange(_ change: ZoneChange) async {
        guard confirm.take(change) else { return }
        await set(change.id, change.value)
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
            if case .permissionDenied(let why) = error, Self.isAboutToken(why) { canChange = false; formError = StorageCopy.editHint("Zone Settings Edit") }
            else if case .permissionDenied(let why?) = error { formError = why }
            else { formError = error.errorDescription }
            await load()  // the change may have landed before the error (a timeout), so show what Cloudflare really has
        } catch { formError = "Couldn't save that change."; await load() }
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
            if case .permissionDenied(let why) = error, Self.isAboutToken(why) { canPurge = false; formError = StorageCopy.editHint("Cache Purge") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't purge the cache." }
    }

    /// A 403 only means "the token lacks the permission" when Cloudflare says nothing else (plan limits and the like name themselves).
    private static func isAboutToken(_ why: String?) -> Bool {
        guard let m = why?.lowercased() else { return true }
        return m.contains("auth") || m.contains("permission")
    }
}
