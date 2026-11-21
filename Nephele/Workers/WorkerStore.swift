import Foundation
import Observation
import CloudflareKit

/// Everything about one open Worker. Later tasks add settings, triggers, versions, code and logs.
@MainActor @Observable
final class WorkerStore {
    let script: WorkerScript
    private(set) var latestDeployment: LoadState<WorkerDeployment?> = .idle
    /// Starts true: a token's scopes can't be read cheaply, so the first forbidden write turns it off.
    private(set) var canWrite = true
    var formError: String?
    private(set) var settings: LoadState<WorkerSettings> = .idle
    private(set) var secretNames: LoadState<[String]> = .idle
    private(set) var workersDev: Bool?
    var triggers: LoadState<WorkerTriggers> = .idle
    let confirm = ConfirmGate<WorkerChange>()

    @ObservationIgnored let session: Session

    init(script: WorkerScript, session: Session) {
        self.script = script
        self.session = session
    }

    func noteWriteDenied() { canWrite = false }

    func load() async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
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
        guard let client = session.client, let account = session.selectedAccountID else { return }
        let name = script.id
        if settings.value == nil { settings = .loading }
        if secretNames.value == nil { secretNames = .loading }
        async let s = Result { try await client.workerSettings(accountID: account, script: name) }
        async let n = Result { try await client.workerSecretNames(accountID: account, script: name) }
        async let d = Result { try await client.workersDevSubdomain(accountID: account, script: name) }
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
        guard var bindings = settings.value?.bindings else { return }
        bindings.removeAll { $0.name == name }
        bindings.append(.plain(name: name, text: value))
        await saveSettings(WorkerSettingsChange(bindings: bindings))
    }

    func setSecret(name: String, value: String) async {
        formError = nil
        guard validBindingName(name) else { formError = "Use letters, digits, _ or $ for a secret name, and don't start with a digit."; return }
        guard !value.isEmpty else { formError = "Enter a value for the secret."; return }
        await write { client, account, script in
            try await client.setWorkerSecret(accountID: account, script: script, name: name, value: value)
            self.secretNames = .loaded(try await client.workerSecretNames(accountID: account, script: script))
        }
    }

    func requestChange(_ change: WorkerChange) { formError = nil; confirm.request(change) }

    func confirmChange(_ change: WorkerChange) async {
        guard confirm.take(change) else { return }
        switch change {
        case .removeVar(let n), .removeBinding(let n):
            guard let current = settings.value?.bindings else { return }
            await saveSettings(WorkerSettingsChange(bindings: current.filter { $0.name != n }))
        case .deleteSecret(let n):
            await write { client, account, script in
                try await client.deleteWorkerSecret(accountID: account, script: script, name: n)
                self.secretNames = .loaded((self.secretNames.value ?? []).filter { $0 != n })
            }
        case .toggleWorkersDev(let on):
            await write { client, account, script in
                try await client.setWorkersDevSubdomain(accountID: account, script: script, enabled: on)
                self.workersDev = on
            }
        case .removeCron, .removeRoute, .detachDomain:
            await confirmTriggerChange(change)
        }
    }

    // MARK: Shared

    /// Runs one write. A forbidden reply turns writes off and says which permission to add.
    func write(_ body: (CFClient, String, String) async throws -> Void) async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        formError = nil
        do { try await body(client, account, script.id) }
        catch let error as CloudflareError {
            if case .permissionDenied = error {
                noteWriteDenied()
                formError = "This token can't edit Workers. Add Workers Scripts Edit to it in Cloudflare, then try again."
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
