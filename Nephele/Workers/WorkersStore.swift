import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class WorkersStore {
    private(set) var workers: LoadState<[WorkerScript]> = .idle
    var formError: String?
    /// One store per Worker for the session, so an unsaved draft survives leaving and coming back.
    @ObservationIgnored private var details: [String: WorkerStore] = [:]
    @ObservationIgnored private let session: Session

    init(session: Session) { self.session = session }

    func reset() { workers = .idle; details = [:] }

    func detail(for script: WorkerScript) -> WorkerStore {
        let key = "\(session.selectedAccountID ?? "")/\(script.id)"
        if let existing = details[key] { return existing }
        let store = WorkerStore(script: script, session: session)
        details[key] = store
        return store
    }

    func load(force: Bool = false) async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        let epoch = session.identityEpoch
        if workers.value == nil { workers = .loading }
        do {
            let list = try await client.workers(accountID: account).sorted { $0.id < $1.id }
            guard epoch == session.identityEpoch else { return }
            workers = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if workers.value == nil { workers = .failed(error) }
        } catch {
            if workers.value == nil { workers = .failed(.transport("unknown")) }
        }
    }

    private static let editHint = "This token can't edit Workers. Add Workers Scripts Edit to it in Cloudflare, then try again."

    /// Creates a Worker from a template and uploads its first version. It is not deployed.
    func create(name: String, template: WorkerTemplate) async -> WorkerScript? {
        formError = nil
        guard validWorkerName(name) else { formError = WorkerValidationError.invalidName.errorDescription; return nil }
        guard !(workers.value ?? []).contains(where: { $0.id == name }) else { formError = "You already have a Worker called \(name)."; return nil }
        guard let client = session.client, let account = session.selectedAccountID else { return nil }
        do {
            _ = try await client.createWorker(accountID: account, name: name, template: template)
            let created = WorkerScript(id: name)
            workers = .loaded(((workers.value ?? []) + [created]).sorted { $0.id < $1.id })
            return created
        } catch { report(error, fallback: "Couldn't create that Worker."); return nil }
    }

    /// Deletes a Worker. The caller has had the user type its name; it is checked again here.
    func delete(_ script: WorkerScript, typedName: String) async {
        formError = nil
        guard typedName == script.id else { formError = "Type \(script.id) exactly to delete it."; return }
        guard let client = session.client, let account = session.selectedAccountID else { return }
        do {
            try await client.deleteWorker(accountID: account, script: script.id)
            workers = .loaded((workers.value ?? []).filter { $0.id != script.id })
            details["\(session.selectedAccountID ?? "")/\(script.id)"] = nil
        } catch { report(error, fallback: "Couldn't delete that Worker.") }
    }

    private func report(_ error: any Error, fallback: String) {
        guard let e = error as? CloudflareError else {
            formError = (error as? LocalizedError)?.errorDescription ?? fallback
            return
        }
        if case .permissionDenied = e { formError = Self.editHint } else { session.handle(e); formError = e.errorDescription }
    }
}
