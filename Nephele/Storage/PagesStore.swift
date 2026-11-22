import Foundation
import Observation
import CloudflareKit

enum PagesChange: Equatable, Sendable {
    case retry(PagesDeployment), rollback(PagesDeployment), delete(PagesDeployment)
    private func label(_ d: PagesDeployment) -> String { d.shortId ?? String(d.id.prefix(8)) }
    func title(project: String) -> String {
        switch self {
        case .retry(let d): "Retry \(label(d))?"
        case .rollback(let d): "Roll back to \(label(d))?"
        case .delete(let d): "Delete \(label(d))?"
        }
    }
    func message(project: String) -> String {
        switch self {
        case .retry(let d): "Builds \(label(d)) again for \(project)."
        case .rollback(let d): "Makes \(label(d)) the live production deployment of \(project). Visitors see it straight away."
        case .delete(let d): "Removes \(label(d)) from \(project). This can't be undone."
        }
    }
    var isRetry: Bool { if case .retry = self { true } else { false } }
    var button: String { switch self { case .retry: "Retry"; case .rollback: "Roll back"; case .delete: "Delete" } }
}

@MainActor @Observable
final class PagesStore {
    private(set) var projects: LoadState<[PagesProject]> = .idle
    private(set) var selected: PagesProject?
    private(set) var deployments: LoadState<[PagesDeployment]> = .idle
    private(set) var canWrite = true
    var formError: String?
    let confirm = ConfirmGate<PagesChange>()

    @ObservationIgnored let session: Session
    init(session: Session) { self.session = session }

    func reset() { projects = .idle; selected = nil; deployments = .idle; canWrite = true; formError = nil; confirm.cancel() }

    private var account: String? { session.selectedAccountID }

    func load() async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if projects.value == nil { projects = .loading }
        do {
            let list = try await client.pagesProjects(accountID: account).sorted { $0.name.lowercased() < $1.name.lowercased() }
            guard epoch == session.identityEpoch else { return }
            projects = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if projects.value == nil { projects = .failed(error) }
        } catch { if projects.value == nil { projects = .failed(.transport("unknown")) } }
    }

    func select(_ project: PagesProject?) async {
        selected = project; deployments = .idle; formError = nil
        if project != nil { await loadDeployments() }
    }

    func loadDeployments() async {
        guard let client = session.client, let account, let project = selected else { return }
        let epoch = session.identityEpoch
        deployments = .loading
        do {
            let list = try await client.pagesDeployments(accountID: account, project: project.name)
            guard epoch == session.identityEpoch, selected == project else { return }
            deployments = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch, selected == project else { return }
            session.handle(error)
            deployments = .failed(error)
        } catch { deployments = .failed(.transport("unknown")) }
    }

    func request(_ change: PagesChange) { formError = nil; confirm.request(change) }

    func confirmChange(_ change: PagesChange) async {
        guard confirm.take(change), let project = selected else { return }
        await write { client, account, isCurrent in
            switch change {
            case .retry(let d): try await client.retryPagesDeployment(accountID: account, project: project.name, id: d.id)
            case .rollback(let d): try await client.rollbackPagesDeployment(accountID: account, project: project.name, id: d.id)
            case .delete(let d):
                try await client.deletePagesDeployment(accountID: account, project: project.name, id: d.id)
                guard isCurrent() else { return }
                self.deployments = .loaded((self.deployments.value ?? []).filter { $0.id != d.id })
                return
            }
            guard isCurrent(), self.selected == project else { return }
            await self.loadDeployments()
        }
    }

    func deleteProject(_ project: PagesProject, typedName: String) async {
        formError = nil
        guard typedName == project.name else { formError = "Type \(project.name) exactly to delete it."; return }
        await write { client, account, isCurrent in
            try await client.deletePagesProject(accountID: account, name: project.name)
            guard isCurrent() else { return }
            self.projects = .loaded((self.projects.value ?? []).filter { $0.name != project.name })
            if self.selected == project { self.selected = nil; self.deployments = .idle }
        }
    }

    private func write(_ body: (CFClient, String, @MainActor @Sendable () -> Bool) async throws -> Void) async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do { try await body(client, account, { [session] in epoch == session.identityEpoch }) }
        catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if case .permissionDenied = error { canWrite = false; formError = StorageCopy.editHint("Cloudflare Pages Edit") }
            else { formError = error.errorDescription }
        } catch { formError = "Couldn't save that change." }
    }
}
