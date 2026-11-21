import Foundation
import CloudflareKit

extension WorkerStore {
    /// The version taking the most traffic in the newest deployment.
    var liveVersionID: String? {
        deployments.value?.first?.versions.max { $0.percentage < $1.percentage }?.versionId
    }

    func isLive(_ version: WorkerVersion) -> Bool { version.id == liveVersionID }

    func loadVersions() async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        let name = script.id
        if versions.value == nil { versions = .loading }
        if deployments.value == nil { deployments = .loading }
        async let v = Result { try await client.workerVersions(accountID: account, script: name) }
        async let d = Result { try await client.deployments(accountID: account, script: name) }
        let (vr, dr) = await (v, d)
        switch vr {
        case .success(let list): versions = .loaded(list)
        case .failure(let e): versions = .failed(note(e))
        }
        switch dr {
        case .success(let list): deployments = .loaded(list); latestDeployment = .loaded(list.first)
        case .failure(let e): deployments = .failed(note(e))
        }
    }

    /// Asks to make `version` live. Nothing is sent until the change is confirmed.
    func requestDeploy(_ version: WorkerVersion) {
        guard !isLive(version) else { return }
        let rollback = liveVersion.map { isOlder(version, than: $0) } ?? false
        requestChange(.deploy(versionID: version.id, label: String(version.id.prefix(8)), rollback: rollback))
    }

    func deploy(versionID: String, message: String) async {
        await write { client, account, name in
            _ = try await client.deployVersion(accountID: account, script: name, versionID: versionID, message: message)
            await self.loadVersions()
        }
    }

    private var liveVersion: WorkerVersion? { versions.value?.first { $0.id == liveVersionID } }

    private func isOlder(_ a: WorkerVersion, than b: WorkerVersion) -> Bool {
        if let x = a.number, let y = b.number { return x < y }
        return (a.createdOn ?? .distantPast) < (b.createdOn ?? .distantPast)
    }
}
