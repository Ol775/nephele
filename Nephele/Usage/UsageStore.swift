import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class UsageStore {
    private(set) var range: UsageRange = .h24
    private(set) var traffic: LoadState<TrafficSummary> = .idle
    private(set) var meters: LoadState<[Meter]> = .idle

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let domains: DomainsStore

    init(session: Session, domains: DomainsStore) {
        self.session = session
        self.domains = domains
    }

    func load(force: Bool = false) async {
        await domains.load(force: force)
        async let t: Void = loadTraffic()
        async let m: Void = loadMeters()
        _ = await (t, m)
    }

    func reset() {
        traffic = .idle
        meters = .idle
    }

    func setRange(_ newRange: UsageRange) async {
        range = newRange
        await loadTraffic()
    }

    private func loadTraffic() async {
        guard let client = session.client else { return }
        if traffic.value == nil { traffic = .loading }
        let ids = (domains.zones.value ?? []).map(\.id)
        do { traffic = .loaded(try await client.traffic(zoneIDs: ids, range: range)) }
        catch let error as CloudflareError {
            session.handle(error)
            if traffic.value == nil { traffic = .failed(error) }
        } catch { if traffic.value == nil { traffic = .failed(.transport("unknown")) } }
    }

    private func loadMeters() async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        if meters.value == nil { meters = .loading }
        do { meters = .loaded(try await client.accountMeters(accountID: account)) }
        catch let error as CloudflareError {
            session.handle(error)
            if meters.value == nil { meters = .failed(error) }
        } catch { if meters.value == nil { meters = .failed(.transport("unknown")) } }
    }
}
