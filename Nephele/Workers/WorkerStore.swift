import Foundation
import Observation
import CloudflareKit

/// Everything about one open Worker. Later tasks add settings, triggers, versions, code and logs.
@MainActor @Observable
final class WorkerStore {
    let script: WorkerScript
    var latestDeployment: LoadState<WorkerDeployment?> = .idle
    /// Starts true: a token's scopes can't be read cheaply, so the first forbidden write turns it off.
    private(set) var canWrite = true
    var formError: String?
    private(set) var settings: LoadState<WorkerSettings> = .idle
    private(set) var secretNames: LoadState<[String]> = .idle
    private(set) var workersDev: Bool?
    var triggers: LoadState<WorkerTriggers> = .idle
    var versions: LoadState<[WorkerVersion]> = .idle
    var deployments: LoadState<[WorkerDeployment]> = .idle
    var code: LoadState<WorkerCode> = .idle
    var draft = ""
    var loadedText: String?
    var lastSavedVersionID: String?
    let confirm = ConfirmGate<WorkerChange>()

    @ObservationIgnored let session: Session
    /// The account this store was opened under. After an account switch the store refuses to load or write.
    @ObservationIgnored let accountID: String?

    init(script: WorkerScript, session: Session, accountID: String? = nil) {
        self.script = script
        self.session = session
        self.accountID = accountID ?? session.selectedAccountID
    }

    static let wrongAccount = "This Worker belongs to a different account than the one now selected. Go back to the Workers list."

    /// The pinned account, only while it is still the selected one.
    var activeAccount: String? { accountID.flatMap { $0 == session.selectedAccountID ? $0 : nil } }

    func noteWriteDenied() { canWrite = false }

    func load() async {
        guard let client = session.client, let account = activeAccount else { return }
        if latestDeployment.value == nil { latestDeployment = .loading }
        do {
            latestDeployment = .loaded(try await client.deployments(accountID: account, script: script.id).first)
        } catch let error as CloudflareError {
            session.handle(error)
            latestDeployment = .failed(error)
        } catch {
            latestDeployment = .failed(.transport("unknown"))
        }
    }

    // MARK: Settings, variables, secrets

    func loadSettings() async {
        guard let client = session.client, let account = activeAccount else { return }
        let name = script.id
        if settings.value == nil { settings = .loading }
        if secretNames.value == nil { secretNames = .loading }
        async let s = capture { try await client.workerSettings(accountID: account, script: name) }
        async let n = capture { try await client.workerSecretNames(accountID: account, script: name) }
        async let d = capture { try await client.workersDevSubdomain(accountID: account, script: name) }
        let (sr, nr, dr) = await (s, n, d)
        switch sr {
        case .success(let v): settings = .loaded(v)
        case .failure(let e): settings = .failed(note(e))
        }
        switch nr {
        case .success(let v): secretNames = .loaded(v)
        case .failure(let e): secretNames = .failed(note(e))
        }
        if case .success(let v) = dr { workersDev = v }
    }

    func saveSettings(_ change: WorkerSettingsChange) async {
        await write { client, account, name in
            self.settings = .loaded(try await client.updateWorkerSettings(accountID: account, script: name, change))
        }
    }

    /// Adds or replaces a plain variable, keeping every other binding as it is.
    func setVar(name: String, value: String) async {
        formError = nil
        guard validBindingName(name) else { formError = "Use letters, digits, _ or $ for a variable name, and don't start with a digit."; return }
        await write { client, account, script in
            let current = try await self.freshSettings(client, account, script)
            if let existing = current.bindings.first(where: { $0.name == name }), existing.type != "plain_text" {
                throw StoreMessage(text: "\(name) is already used by a \(existing.isSecret ? "secret" : "\(existing.type) binding"). Pick a different variable name.")
            }
            var bindings = current.bindings.filter { $0.name != name }
            bindings.append(.plain(name: name, text: value))
            self.settings = .loaded(try await client.updateWorkerSettings(accountID: account, script: script, WorkerSettingsChange(bindings: bindings)))
        }
    }

    /// The Worker's current settings straight from Cloudflare, so a bindings save never works from a stale snapshot.
    func freshSettings(_ client: CFClient, _ account: String, _ script: String) async throws -> WorkerSettings {
        let current = try await client.workerSettings(accountID: account, script: script)
        settings = .loaded(current)
        return current
    }

    /// After a secret is set or deleted: refresh names and settings. Failures here don't change write access.
    private func refreshAfterSecretChange() async {
        guard formError == nil, let client = session.client, let account = activeAccount else { return }
        if let names = try? await client.workerSecretNames(accountID: account, script: script.id) { secretNames = .loaded(names) }
        if let current = try? await client.workerSettings(accountID: account, script: script.id) { settings = .loaded(current) }
    }

    func setSecret(name: String, value: String) async {
        formError = nil
        guard validBindingName(name) else { formError = "Use letters, digits, _ or $ for a secret name, and don't start with a digit."; return }
        guard !value.isEmpty else { formError = "Enter a value for the secret."; return }
        await write { client, account, script in
            try await client.setWorkerSecret(accountID: account, script: script, name: name, value: value)
        }
        await refreshAfterSecretChange()
    }

    func requestChange(_ change: WorkerChange) { formError = nil; confirm.request(change) }

    func confirmChange(_ change: WorkerChange) async {
        guard confirm.take(change) else { return }
        switch change {
        case .removeVar(let n), .removeBinding(let n):
            await write { client, account, script in
                let current = try await self.freshSettings(client, account, script)
                self.settings = .loaded(try await client.updateWorkerSettings(accountID: account, script: script, WorkerSettingsChange(bindings: current.bindings.filter { $0.name != n })))
            }
        case .deleteSecret(let n):
            await write { client, account, script in
                try await client.deleteWorkerSecret(accountID: account, script: script, name: n)
            }
            await refreshAfterSecretChange()
        case .toggleWorkersDev(let on):
            await write { client, account, script in
                try await client.setWorkersDevSubdomain(accountID: account, script: script, enabled: on)
                self.workersDev = on
            }
        case .removeCron, .removeRoute, .detachDomain:
            await confirmTriggerChange(change)
        case .deploy(let versionID, let label, let rollback):
            await deploy(versionID: versionID, message: rollback ? "Rolled back to \(label) from Nephele" : "Deployed \(label) from Nephele")
        }
    }

    // MARK: Shared

    struct StoreMessage: Error { let text: String }

    /// Runs one write. A forbidden reply turns writes off and says which permission to add, unless `deniedHint`
    /// names a narrower permission (routes, domains), in which case other writes stay available.
    func write(deniedHint: String? = nil, _ body: (CFClient, String, String) async throws -> Void) async {
        formError = nil
        guard let client = session.client else { return }
        guard let account = activeAccount else { formError = Self.wrongAccount; return }
        do { try await body(client, account, script.id) }
        catch let message as StoreMessage { formError = message.text }
        catch let error as CloudflareError {
            if case .permissionDenied = error {
                if let deniedHint { formError = deniedHint } else {
                    noteWriteDenied()
                    formError = "This token can't edit Workers. Add Workers Scripts Edit to it in Cloudflare, then try again."
                }
            } else {
                session.handle(error)
                formError = error.errorDescription
            }
        } catch { formError = "Couldn't save that change." }
    }

    func note(_ error: any Error) -> CloudflareError {
        guard let e = error as? CloudflareError else { return .transport("unknown") }
        session.handle(e)
        return e
    }
}
