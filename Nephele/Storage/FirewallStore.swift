import Foundation
import Observation
import CloudflareKit

/// A WAF change that goes live straight away, so it is confirmed first.
enum FirewallChange: Equatable, Sendable {
    case create(FirewallRuleDraft), enable(FirewallRule), delete(FirewallRule)
    var title: String { switch self { case .create: "Add this rule?"; case .enable: "Turn this rule on?"; case .delete: "Delete this rule?" } }
    var button: String { switch self { case .create: "Add rule"; case .enable: "Turn on"; case .delete: "Delete rule" } }
    var message: String {
        switch self {
        case .create(let d): d.action == "log" ? "The rule only logs matches." : "Matching requests are \(Self.verb(d.action)) straight away, for every visitor. A wrong expression can lock real visitors out."
        case .enable(let r): "Matching requests are \(Self.verb(r.action)) straight away."
        case .delete(let r): "\(r.description?.isEmpty == false ? r.description! : "This rule") stops applying straight away. It can't be undone."
        }
    }
    static func verb(_ action: String) -> String {
        switch action { case "block": "blocked"; case "log": "logged"; default: "challenged (\(action.replacingOccurrences(of: "_", with: " ")))" }
    }
}

/// WAF custom rules for one zone (the `http_request_firewall_custom` phase).
@MainActor @Observable
final class FirewallStore {
    let zone: Zone
    private(set) var rules: LoadState<[FirewallRule]> = .idle
    private(set) var canWrite = true
    private(set) var busy = false
    var formError: String?
    let confirm = ConfirmGate<FirewallChange>()
    @ObservationIgnored private var rulesetID: String?
    @ObservationIgnored let session: Session
    init(zone: Zone, session: Session) { self.zone = zone; self.session = session }

    func load() async {
        guard let client = session.client else { return }
        let epoch = session.identityEpoch
        if rules.value == nil { rules = .loading }
        do {
            let set = try await client.firewallRuleset(zoneID: zone.id)
            guard epoch == session.identityEpoch else { return }
            rulesetID = set?.id; rules = .loaded(set?.rules ?? [])
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if rules.value == nil { rules = .failed(error) } else { formError = error.errorDescription }
        } catch { if rules.value == nil { rules = .failed(.transport("unknown")) } }
    }

    func request(_ change: FirewallChange) {
        formError = nil
        if case .create(let d) = change, !d.isValid { formError = "A rule needs an action and an expression."; return }
        confirm.request(change)
    }

    /// Turning a rule off needs no confirmation: it only removes protection.
    func disable(_ rule: FirewallRule) async {
        formError = nil
        await write { client, isCurrent in
            guard let id = rulesetID else { return }
            let set = try await client.setFirewallRule(zoneID: zone.id, rulesetID: id, rule: rule, enabled: false)
            guard isCurrent() else { return }
            rules = .loaded(set.rules ?? [])
        }
    }

    func confirmChange(_ change: FirewallChange) async {
        guard confirm.take(change) else { return }
        await write { client, isCurrent in
            let set: FirewallRuleset
            switch change {
            case .create(let d):
                // Re-read first: PUT on the entrypoint replaces every rule, so only use it when Cloudflare confirms there is no ruleset.
                let current = try await client.firewallRuleset(zoneID: zone.id)
                set = try await client.createFirewallRule(zoneID: zone.id, rulesetID: current?.id, d)
            case .enable(let r):
                guard let id = rulesetID else { return }
                set = try await client.setFirewallRule(zoneID: zone.id, rulesetID: id, rule: r, enabled: true)
            case .delete(let r):
                guard let id = rulesetID else { return }
                try await client.deleteFirewallRule(zoneID: zone.id, rulesetID: id, id: r.id)
                guard isCurrent() else { return }
                rules = .loaded((rules.value ?? []).filter { $0.id != r.id })
                return
            }
            guard isCurrent() else { return }
            rulesetID = set.id; rules = .loaded(set.rules ?? [])
        }
    }

    private func write(_ body: (CFClient, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        switch await guardedWrite(session, permission: "Zone WAF Edit", body) {
        case .done, .stale: break
        case .denied(let m): canWrite = false; formError = m
        case .failed(let m): formError = m
        }
    }
}
