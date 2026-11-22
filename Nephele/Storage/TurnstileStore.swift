import Foundation
import Observation
import CloudflareKit

/// Turnstile widgets for the account. A new widget's secret is shown once, then dropped.
@MainActor @Observable
final class TurnstileStore {
    private(set) var widgets: LoadState<[TurnstileWidget]> = .idle
    private(set) var canWrite = true
    private(set) var busy = false
    private(set) var newSecret: NewServiceSecret?
    var formError: String?
    @ObservationIgnored let session: Session
    init(session: Session) { self.session = session }

    func reset() { widgets = .idle; canWrite = true; formError = nil }  // a freshly created secret survives: it can never be shown again

    func load() async {
        guard let account = session.selectedAccountID else { return }
        await loadList(session, self, \.widgets) { try await $0.turnstileWidgets(accountID: account).sorted { $0.name.lowercased() < $1.name.lowercased() } }
    }

    func create(name: String, domains text: String, mode: String) async {
        formError = nil
        guard validTunnelName(name) else { formError = "Give the widget a name (up to 100 characters)."; return }
        let domains = parseTurnstileDomains(text)
        guard !domains.isEmpty, domains.allSatisfy(validHostname) else { formError = "Enter hostnames only, such as example.com. No https:// or paths."; return }
        await write { client, isCurrent in
            guard let account = session.selectedAccountID else { return }
            let made = try await client.createTurnstile(accountID: account, name: name, domains: domains, mode: mode)
            // The secret is handed over even if the account changed meanwhile: it exists nowhere else.
            newSecret = NewServiceSecret(name: made.widget.name, clientID: made.widget.sitekey, secret: made.secret)
            guard isCurrent() else { return }
            widgets = .loaded(((widgets.value ?? []) + [made.widget]).sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
    }

    func dismissSecret() { newSecret = nil }

    func delete(_ widget: TurnstileWidget, typedName: String) async {
        formError = nil
        guard typedName == widget.name else { formError = "Type \(widget.name) exactly to delete it."; return }
        await write { client, isCurrent in
            guard let account = session.selectedAccountID else { return }
            try await client.deleteTurnstile(accountID: account, sitekey: widget.sitekey)
            guard isCurrent() else { return }
            widgets = .loaded((widgets.value ?? []).filter { $0.sitekey != widget.sitekey })
        }
    }

    private func write(_ body: (CFClient, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        switch await guardedWrite(session, permission: "Turnstile Sites Edit", body) {
        case .done, .stale: break
        case .denied(let m): canWrite = false; formError = m
        case .failed(let m): formError = m
        }
    }
}
