import Foundation
import Observation
import CloudflareKit

enum SignInError: Error, Equatable, LocalizedError {
    case invalidFormat, noAccount
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "A Cloudflare API token is 40 characters of letters, numbers, hyphens and underscores."
        case .noAccount: "This token can't see any account. Add Account Settings Read, then try again."
        }
    }
}

@MainActor @Observable
final class Session {
    enum State: Equatable { case signedOut, verifying, ready }

    private(set) var state: State = .signedOut
    private(set) var accounts: [CFAccount] = []
    var selectedAccountID: String?
    private(set) var permissions: [PermissionStatus] = []
    private(set) var client: CFClient?
    private(set) var tokenHint = ""
    private(set) var signInError: String?

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let makeClient: (String) -> CFClient

    init(tokenStore: TokenStore = TokenStore(), makeClient: @escaping (String) -> CFClient = { CFClient(token: $0) }) {
        self.tokenStore = tokenStore
        self.makeClient = makeClient
    }

    var missingPermissions: [PermissionStatus] { permissions.filter { !$0.granted } }
    var selectedAccount: CFAccount? { accounts.first { $0.id == selectedAccountID } }

    static func isPlausibleToken(_ s: String) -> Bool { s.wholeMatch(of: /[A-Za-z0-9_-]{40}/) != nil }

    func signIn(token raw: String) async throws {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleToken(token) else { throw SignInError.invalidFormat }
        try await establish(token: token, persist: true)
    }

    /// Uses the stored token at launch. A network failure keeps the token so the user can retry.
    func restore() async {
        guard state == .signedOut, let token = tokenStore.load() else { return }
        do {
            try await establish(token: token, persist: false)
        } catch CloudflareError.unauthorized {
            tokenStore.delete()
            signInError = CloudflareError.unauthorized.errorDescription
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Cloudflare. Check your connection and try again."
        }
    }

    func signOut() {
        tokenStore.delete()
        clear()
    }

    /// Stores call this with any error from a request: a rejected token ends the session.
    func handle(_ error: CloudflareError) {
        guard case .unauthorized = error else { return }
        signOut()
        signInError = CloudflareError.unauthorized.errorDescription
    }

    private func establish(token: String, persist: Bool) async throws {
        state = .verifying
        signInError = nil
        let c = makeClient(token)
        do {
            _ = try await c.verifyToken()
            let found = try await c.accounts()
            guard let first = found.first else { throw SignInError.noAccount }
            let zones: CFEnvelope<[Zone]>? = try? await c.get("/zones", query: [URLQueryItem(name: "per_page", value: "1")])
            let checked = await c.probePermissions(accountID: first.id, zoneID: zones?.result?.first?.id)
            if persist { try tokenStore.save(token) }
            client = c
            accounts = found
            selectedAccountID = first.id
            permissions = checked
            tokenHint = String(token.suffix(4))
            state = .ready
        } catch {
            clear()
            throw error
        }
    }

    private func clear() {
        client = nil; accounts = []; selectedAccountID = nil; permissions = []; tokenHint = ""
        state = .signedOut
    }
}
