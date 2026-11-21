import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class DomainsStore {
    private(set) var zones: LoadState<[Zone]> = .idle
    private(set) var lastError: CloudflareError?

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ttl: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var seenEpoch = 0

    init(session: Session, ttl: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.ttl = ttl
        self.now = now
    }

    func clearCache() { loadedAt = nil }

    func load(force: Bool = false) async {
        guard let client = session.client else { return }
        let fresh = loadedAt.map { now().timeIntervalSince($0) <= ttl } ?? false
        guard force || !fresh || seenEpoch != session.cacheEpoch else { return }
        if zones.value == nil { zones = .loading }
        do {
            zones = .loaded(try await client.zones())
            loadedAt = now()
            seenEpoch = session.cacheEpoch
            lastError = nil
        } catch let error as CloudflareError {
            session.handle(error)
            lastError = error
            if zones.value == nil { zones = .failed(error) }
        } catch {
            if zones.value == nil { zones = .failed(.transport("unknown")) }
        }
    }
}
