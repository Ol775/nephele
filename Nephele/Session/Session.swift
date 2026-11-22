import Foundation
import Observation
import CloudflareKit

enum SignInError: Error, Equatable, LocalizedError {
    case invalidFormat, noAccount, inactive
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "That doesn't look like a Cloudflare API token. New tokens start with cfut_ or cfat_; older ones are 40 letters and numbers."
        case .noAccount: "This token can't see any account. Add Account Settings Read, then try again."
        case .inactive: "That token isn't active. Check it in the Cloudflare dashboard, or create a new one."
        }
    }
}

@MainActor @Observable
final class Session {
    enum State: Equatable { case signedOut, verifying, ready }

    private(set) var state: State = .signedOut
    private(set) var accounts: [CFAccount] = []
    private(set) var selectedAccountID: String?
    private(set) var permissions: [PermissionStatus] = []
    private(set) var client: CFClient?
    private(set) var tokenHint = ""
    private(set) var signInError: String?
    private(set) var canRetryRestore = false
    /// True while the stored token is being read from the Keychain. After an update macOS may hold that read
    /// behind a permission prompt, so it runs off the main thread and the window says what it is waiting for.
    private(set) var readingKeychain = false
    /// Stores compare this to the value they last loaded at; bumping it makes every store refetch.
    private(set) var cacheEpoch = 0
    /// Bumps when the signed-in identity changes (sign in, sign out, account switch) so stores drop their data.
    private(set) var identityEpoch = 0
    @ObservationIgnored private(set) var revalidationTask: Task<Void, Never>?

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let makeClient: (String) -> CFClient
    @ObservationIgnored private var verifyAccountID: String?
    @ObservationIgnored private var lastRevalidation: Date?

    init(tokenStore: TokenStore = TokenStore(), makeClient: @escaping (String) -> CFClient = { CFClient(token: $0) }) {
        self.tokenStore = tokenStore
        self.makeClient = makeClient
    }

    var missingPermissions: [PermissionStatus] { permissions.filter { !$0.granted } }

    static func isPlausibleToken(_ s: String) -> Bool {
        s.wholeMatch(of: /[A-Za-z0-9_-]{40}/) != nil || s.wholeMatch(of: /cf(ut|at)_[A-Za-z0-9]{40}[A-Za-z0-9]{4,16}/) != nil
    }

    func signIn(token raw: String) async throws {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleToken(token) else { throw SignInError.invalidFormat }
        try await establish(token: token, persist: true)
    }

    /// Uses the stored token at launch. A network failure keeps the token so the user can retry.
    func restore() async {
        guard state == .signedOut, !readingKeychain else { return }
        readingKeychain = true
        let store = tokenStore
        let stored = await Task.detached { store.load() }.value
        readingKeychain = false
        guard state == .signedOut, let token = stored else { return }
        canRetryRestore = false
        do {
            try await establish(token: token, persist: false)
        } catch CloudflareError.unauthorized {
            tokenStore.delete()
            signInError = CloudflareError.unauthorized.errorDescription
        } catch {
            canRetryRestore = true
            signInError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Cloudflare. Check your connection and try again."
        }
    }

    /// Retries while the network is not up yet (for example at login).
    func restoreWithRetry(every seconds: Double = 15) async {
        await restore()
        while canRetryRestore, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(seconds))
            await restore()
        }
    }

    /// Demo mode only: establishes the session without saving the token.
    func signInForDemo(token: String) async { try? await establish(token: token, persist: false) }

    func selectAccount(_ id: String?) {
        guard id != selectedAccountID else { return }
        selectedAccountID = id
        identityEpoch += 1
    }

    func clearCache() { cacheEpoch += 1 }

    func signOut() {
        tokenStore.delete()
        clear()
    }

    /// Stores call this with any error from a request. A rejected token ends the session; a permission
    /// error might really be a revoked token (Cloudflare answers some of those with 403), so check once.
    func handle(_ error: CloudflareError) {
        switch error {
        case .unauthorized:
            signOut()
            signInError = CloudflareError.unauthorized.errorDescription
        case .permissionDenied:
            if revalidationTask == nil {
                revalidationTask = Task { [weak self] in
                    await self?.revalidate()
                    self?.revalidationTask = nil
                }
            }
        default: break
        }
    }

    /// Re-checks the token at most once a minute and signs out if it is no longer valid.
    func revalidate(now: Date = Date()) async {
        guard state == .ready, let client else { return }
        if let last = lastRevalidation, now.timeIntervalSince(last) < 60 { return }
        lastRevalidation = now
        do {
            if try await client.verifyToken(accountID: verifyAccountID).status != "active" { expire() }
        } catch CloudflareError.unauthorized {
            expire()
        } catch {}
    }

    private func expire() {
        signOut()
        signInError = CloudflareError.unauthorized.errorDescription
    }

    private func establish(token: String, persist: Bool) async throws {
        // Replacing a token in Settings must not tear down the working session if the new one is wrong.
        let wasReady = state == .ready
        if !wasReady { state = .verifying }
        signInError = nil
        let c = makeClient(token)
        do {
            let ownedByAccount = token.hasPrefix("cfat_")
            let status: TokenStatus
            let found: [CFAccount]
            if ownedByAccount {
                found = try await c.accounts()
                guard let first = found.first else { throw SignInError.noAccount }
                status = try await c.verifyToken(accountID: first.id)
            } else {
                status = try await c.verifyToken()
                found = try await c.accounts()
            }
            guard status.status == "active" else { throw SignInError.inactive }
            guard let first = found.first else { throw SignInError.noAccount }
            let zones: CFEnvelope<[Zone]>? = try? await c.get("/zones", query: [URLQueryItem(name: "per_page", value: "1")])
            let checked = await c.probePermissions(accountID: first.id, zoneID: zones?.result?.first?.id)
            if persist { try tokenStore.save(token) }
            client = c
            verifyAccountID = ownedByAccount ? first.id : nil
            accounts = found
            selectedAccountID = first.id
            permissions = checked
            tokenHint = String(token.suffix(4))
            lastRevalidation = nil
            identityEpoch += 1
            state = .ready
        } catch {
            if !wasReady { clear() }
            throw error
        }
    }

    private func clear() {
        client = nil; accounts = []; selectedAccountID = nil; permissions = []; tokenHint = ""
        verifyAccountID = nil
        identityEpoch += 1
        state = .signedOut
    }
}
