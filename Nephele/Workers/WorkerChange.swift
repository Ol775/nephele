import Foundation

/// A change to a Worker that is confirmed before it is sent. Each names its target.
enum WorkerChange: Equatable, Sendable {
    case removeVar(String)
    case deleteSecret(String)
    case toggleWorkersDev(Bool)
    case removeBinding(String)
    case deploy(versionID: String, label: String, rollback: Bool)
    case removeCron(String)
    case removeRoute(id: String, pattern: String, zoneID: String)
    case detachDomain(id: String, hostname: String)

    func title(worker: String) -> String {
        switch self {
        case .removeVar(let n): "Remove variable \(n)?"
        case .deleteSecret(let n): "Delete secret \(n)?"
        case .toggleWorkersDev(let on): on ? "Turn on workers.dev for \(worker)?" : "Turn off workers.dev for \(worker)?"
        case .removeBinding(let n): "Remove binding \(n)?"
        case .deploy(_, let label, let rollback): rollback ? "Roll back \(worker) to version \(label)?" : "Deploy version \(label) of \(worker)?"
        case .removeCron(let c): "Remove cron trigger \(c)?"
        case .removeRoute(_, let p, _): "Remove route \(p)?"
        case .detachDomain(_, let h): "Remove custom domain \(h)?"
        }
    }

    func message(worker: String) -> String {
        switch self {
        case .removeVar(let n): "\(worker) will stop receiving \(n). Code that reads it gets undefined."
        case .deleteSecret(let n): "\(worker) will lose the secret \(n). This can't be undone, and its value can't be read back."
        case .toggleWorkersDev(let on): on ? "\(worker) becomes reachable on its workers.dev address." : "\(worker) stops answering on its workers.dev address."
        case .removeBinding(let n): "\(worker) will lose its \(n) binding. Code that uses it will fail until you add it back."
        case .deploy(_, let label, let rollback): rollback ? "Version \(label) takes 100% of \(worker)'s traffic straight away. The code now live is replaced, but stays in the version list." : "Version \(label) takes 100% of \(worker)'s traffic straight away."
        case .removeCron(let c): "\(worker) will stop running on the schedule \(c)."
        case .removeRoute(_, let p, _): "Requests matching \(p) will no longer reach \(worker)."
        case .detachDomain(_, let h): "\(h) will stop pointing at \(worker)."
        }
    }

    var confirmLabel: String {
        switch self {
        case .removeVar, .removeBinding, .removeCron, .removeRoute, .detachDomain: "Remove"
        case .deleteSecret: "Delete secret"
        case .toggleWorkersDev(let on): on ? "Turn on" : "Turn off"
        case .deploy(_, _, let rollback): rollback ? "Roll back" : "Deploy"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .toggleWorkersDev(let on): !on
        case .deploy(_, _, let rollback): rollback
        default: true
        }
    }
}
