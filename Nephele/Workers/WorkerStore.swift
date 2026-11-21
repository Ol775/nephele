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
}
