import Foundation
import Observation
import CloudflareKit

enum ZeroTrustTarget: Equatable, Sendable, Identifiable {
    case tunnel(Tunnel), app(AccessApp), token(ServiceToken), gateway(GatewayRule)
    var name: String { switch self { case .tunnel(let t): t.name; case .app(let a): a.name; case .token(let t): t.name; case .gateway(let g): g.name } }
    var id: String { switch self { case .tunnel(let t): "t-\(t.id)"; case .app(let a): "a-\(a.id)"; case .token(let t): "s-\(t.id)"; case .gateway(let g): "g-\(g.id)" } }
    var kind: String { switch self { case .tunnel: "tunnel"; case .app: "application"; case .token: "service token"; case .gateway: "Gateway rule" } }
    var section: ZeroTrustSection { switch self { case .tunnel: .tunnels; case .app: .apps; case .token: .tokens; case .gateway: .gateway } }
}

enum ZeroTrustSection: Hashable, Sendable {
    case tunnels, apps, tokens, gateway
    var editPermission: String { switch self { case .tunnels: "Cloudflare Tunnel Edit"; case .apps: "Access: Apps and Policies Edit"; case .tokens: "Access: Service Tokens Edit"; case .gateway: "Zero Trust Edit" } }
}

/// Shown once, right after creation. Held only here until dismissed.
struct NewServiceSecret: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let name: String; let clientID: String?; let secret: String
    var description: String { "NewServiceSecret(\(name), secret hidden)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["name": name]) }
}

@MainActor @Observable
final class ZeroTrustStore {
    private(set) var tunnels: LoadState<[Tunnel]> = .idle
    private(set) var apps: LoadState<[AccessApp]> = .idle
    private(set) var tokens: LoadState<[ServiceToken]> = .idle
    private(set) var gateway: LoadState<[GatewayRule]> = .idle
    private(set) var denied: Set<ZeroTrustSection> = []
    func canWrite(_ section: ZeroTrustSection) -> Bool { !denied.contains(section) }
    private(set) var newSecret: NewServiceSecret?
    var formError: String?

    @ObservationIgnored let session: Session
    init(session: Session) { self.session = session }

    func reset() { tunnels = .idle; apps = .idle; tokens = .idle; gateway = .idle; denied = []; formError = nil }  // a freshly created secret survives: it can never be shown again

    private var account: String? { session.selectedAccountID }

    func loadAll() async {
        await load(\.tunnels) { try await $0.tunnels(accountID: $1).sorted { $0.name.lowercased() < $1.name.lowercased() } }
        await load(\.apps) { try await $0.accessApps(accountID: $1).sorted { $0.name.lowercased() < $1.name.lowercased() } }
        await load(\.tokens) { try await $0.serviceTokens(accountID: $1).sorted { $0.name.lowercased() < $1.name.lowercased() } }
        await load(\.gateway) { try await $0.gatewayRules(accountID: $1).sorted { ($0.precedence ?? 0, $0.name) < ($1.precedence ?? 0, $1.name) } }
    }

    private func load<T: Sendable>(_ key: ReferenceWritableKeyPath<ZeroTrustStore, LoadState<T>>, _ fetch: (CFClient, String) async throws -> T) async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if self[keyPath: key].value == nil { self[keyPath: key] = .loading }
        do {
            let value = try await fetch(client, account)
            guard epoch == session.identityEpoch else { return }
            self[keyPath: key] = .loaded(value)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if self[keyPath: key].value == nil { self[keyPath: key] = .failed(error) }
        } catch { if self[keyPath: key].value == nil { self[keyPath: key] = .failed(.transport("unknown")) } }
    }

    func createTunnel(_ name: String) async {
        formError = nil
        guard validTunnelName(name) else { formError = "Give the tunnel a name (up to 100 characters)."; return }
        await write(.tunnels) { client, account, isCurrent in
            let t = try await client.createTunnel(accountID: account, name: name)
            guard isCurrent() else { return }
            self.tunnels = .loaded(((self.tunnels.value ?? []) + [t]).sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
    }

    func createToken(name: String, duration: String) async {
        formError = nil
        guard validTunnelName(name) else { formError = "Give the token a name (up to 100 characters)."; return }
        await write(.tokens) { client, account, isCurrent in
            let made = try await client.createServiceToken(accountID: account, name: name, duration: duration)
            // The secret is handed over even if the account changed meanwhile: it exists nowhere else.
            self.newSecret = NewServiceSecret(name: made.token.name, clientID: made.token.clientID, secret: made.clientSecret)
            guard isCurrent() else { return }
            self.tokens = .loaded(((self.tokens.value ?? []) + [made.token]).sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
    }

    func dismissSecret() { newSecret = nil }

    func delete(_ target: ZeroTrustTarget, typedName: String) async {
        formError = nil
        guard typedName == target.name else { formError = "Type \(target.name) exactly to delete it."; return }
        await write(target.section) { client, account, isCurrent in
            switch target {
            case .tunnel(let t):
                try await client.deleteTunnel(accountID: account, id: t.id)
                guard isCurrent() else { return }
                self.tunnels = .loaded((self.tunnels.value ?? []).filter { $0.id != t.id })
            case .app(let a):
                try await client.deleteAccessApp(accountID: account, id: a.id)
                guard isCurrent() else { return }
                self.apps = .loaded((self.apps.value ?? []).filter { $0.id != a.id })
            case .token(let t):
                try await client.deleteServiceToken(accountID: account, id: t.id)
                guard isCurrent() else { return }
                self.tokens = .loaded((self.tokens.value ?? []).filter { $0.id != t.id })
            case .gateway(let g):
                try await client.deleteGatewayRule(accountID: account, id: g.id)
                guard isCurrent() else { return }
                self.gateway = .loaded((self.gateway.value ?? []).filter { $0.id != g.id })
            }
        }
    }

    /// Runs one write. `isCurrent` turns false if the account changed meanwhile, so late results aren't applied.
    private func write(_ section: ZeroTrustSection, _ body: (CFClient, String, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do { try await body(client, account, { [session] in epoch == session.identityEpoch }) }
        catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { denied.insert(section); formError = StorageCopy.editHint(section.editPermission) }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }
}
