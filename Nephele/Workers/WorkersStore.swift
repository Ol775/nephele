import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class WorkersStore {
    private(set) var workers: LoadState<[WorkerScript]> = .idle
    /// One store per Worker for the session, so an unsaved draft survives leaving and coming back.
    @ObservationIgnored private var details: [String: WorkerStore] = [:]
    @ObservationIgnored private let session: Session

    init(session: Session) { self.session = session }

    func reset() { workers = .idle; details = [:] }

    func detail(for script: WorkerScript) -> WorkerStore {
        if let existing = details[script.id] { return existing }
        let store = WorkerStore(script: script, session: session)
        details[script.id] = store
        return store
    }

    func load(force: Bool = false) async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        if workers.value == nil { workers = .loading }
        do {
            workers = .loaded(try await client.workers(accountID: account).sorted { $0.id < $1.id })
        } catch let error as CloudflareError {
            session.handle(error)
            if workers.value == nil { workers = .failed(error) }
        } catch {
            if workers.value == nil { workers = .failed(.transport("unknown")) }
        }
    }
}
