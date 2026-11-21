import Foundation
import Observation
import CloudflareKit

enum AlertCategory: Sendable {
    case cert, origin, usage, deploy, security

    static func of(alertType: String) -> AlertCategory? {
        let t = alertType.lowercased()
        if t.contains("ssl") || t.contains("expir") || t.contains("certificate") { return .cert }
        if t.contains("origin_error") || t.contains("edge_error") || t.contains("5xx") { return .origin }
        if t.contains("usage") || t.contains("limit") || t.contains("billing") { return .usage }
        if t.contains("worker") || t.contains("deploy") || t.contains("build") || t.contains("pages") { return .deploy }
        if t.contains("attack") || t.contains("waf") || t.contains("dos") || t.contains("security") || t.contains("bot") { return .security }
        return nil
    }

    func isEnabled(in prefs: NotificationPrefs) -> Bool {
        switch self {
        case .cert: prefs.cert
        case .origin: prefs.origin
        case .usage: prefs.usage
        case .deploy: prefs.deploy
        case .security: prefs.security
        }
    }
}

@MainActor @Observable
final class AlertsStore {
    private(set) var policies: LoadState<[AlertPolicy]> = .idle
    private(set) var events: LoadState<[AlertEvent]> = .idle
    private(set) var lastError: CloudflareError?
    private(set) var acknowledged: Set<String>

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "nephele.alerts.acknowledged"

    init(session: Session, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        acknowledged = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    var openCount: Int { (events.value ?? []).filter { !acknowledged.contains($0.id) }.count }

    func load() async {
        _ = await fetchEvents()
        await loadPolicies()
    }

    /// Returns the fetched history, or nil on failure (the last good events stay in place).
    func fetchEvents() async -> [AlertEvent]? {
        guard let client = session.client, let account = session.selectedAccountID else { return nil }
        if events.value == nil { events = .loading }
        do {
            let list = try await client.alertHistory(accountID: account)
            events = .loaded(list)
            lastError = nil
            return list
        } catch let error as CloudflareError {
            session.handle(error)
            lastError = error
            if events.value == nil { events = .failed(error) }
            return nil
        } catch {
            lastError = .transport("unknown")
            return nil
        }
    }

    func loadPolicies() async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        if policies.value == nil { policies = .loading }
        do { policies = .loaded(try await client.alertPolicies(accountID: account)) }
        catch let error as CloudflareError {
            session.handle(error)
            if policies.value == nil { policies = .failed(error) }
        } catch {}
    }

    func reset() {
        policies = .idle
        events = .idle
        lastError = nil
    }

    func acknowledge(_ id: String) {
        acknowledged.insert(id)
        defaults.set(Array(acknowledged), forKey: Self.key)
    }
}
