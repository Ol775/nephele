import Foundation
import Observation
import CloudflareKit

enum EmailChange: Equatable, Sendable {
    case delete(EmailRule)
    var message: String {
        switch self { case .delete(let r): "Mail to \(r.from ?? "this address") stops being forwarded straight away. It can't be undone." }
    }
}

/// Email Routing for one zone: forwarding rules and the verified destinations they can use.
@MainActor @Observable
final class EmailRoutingStore {
    let zone: Zone
    private(set) var rules: LoadState<[EmailRule]> = .idle
    private(set) var addresses: [EmailAddress] = []
    private(set) var routing: EmailRoutingStatus?
    private(set) var canWrite = true
    private(set) var busy = false
    var formError: String?
    let confirm = ConfirmGate<EmailChange>()
    @ObservationIgnored let session: Session
    init(zone: Zone, session: Session) { self.zone = zone; self.session = session }

    var verified: [EmailAddress] { addresses.filter { $0.verified != nil } }

    func load() async {
        await loadList(session, self, \.rules) { try await $0.emailRules(zoneID: zone.id).sorted { ($0.from ?? "~") < ($1.from ?? "~") } }
        guard let client = session.client, let account = session.selectedAccountID else { return }
        let epoch = session.identityEpoch
        let status = try? await client.emailRoutingStatus(zoneID: zone.id)
        let list = (try? await client.emailAddresses(accountID: account)) ?? []
        guard epoch == session.identityEpoch else { return }
        routing = status; addresses = list
    }

    func create(address: String, destination: String) async {
        formError = nil
        guard validEmail(address) else { formError = "Enter the full address to forward, such as hello@\(zone.name)."; return }
        guard address.lowercased().hasSuffix("@" + zone.name.lowercased()) else { formError = "The address must end in @\(zone.name)."; return }
        guard verified.contains(where: { $0.email == destination }) else { formError = "Pick a destination you've verified."; return }
        await write { client, isCurrent in
            let r = try await client.createEmailRule(zoneID: zone.id, address: address, destination: destination)
            guard isCurrent() else { return }
            rules = .loaded(((rules.value ?? []) + [r]).sorted { ($0.from ?? "~") < ($1.from ?? "~") })
        }
    }

    func toggle(_ rule: EmailRule) async {
        formError = nil
        await write { client, isCurrent in
            let updated = try await client.setEmailRule(zoneID: zone.id, rule: rule, enabled: !(rule.enabled ?? true))
            guard isCurrent() else { return }
            rules = .loaded((rules.value ?? []).map { $0.id == rule.id ? updated : $0 })
        }
    }

    func requestDelete(_ rule: EmailRule) { formError = nil; confirm.request(.delete(rule)) }

    func confirmChange(_ change: EmailChange) async {
        guard confirm.take(change) else { return }
        guard case .delete(let rule) = change else { return }
        await write { client, isCurrent in
            try await client.deleteEmailRule(zoneID: zone.id, id: rule.id)
            guard isCurrent() else { return }
            rules = .loaded((rules.value ?? []).filter { $0.id != rule.id })
        }
    }

    private func write(_ body: (CFClient, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        switch await guardedWrite(session, permission: "Email Routing Rules Edit", body) {
        case .done, .stale: break
        case .denied(let m): canWrite = false; formError = m
        case .failed(let m): formError = m
        }
    }
}
