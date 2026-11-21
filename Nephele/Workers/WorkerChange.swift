import Foundation

/// A change to a Worker that is confirmed before it is sent. Each names its target.
enum WorkerChange: Equatable, Sendable {
    case removeVar(String)
    case deleteSecret(String)
    case toggleWorkersDev(Bool)
    case removeBinding(String)

    func title(worker: String) -> String {
        switch self {
        case .removeVar(let n): "Remove variable \(n)?"
        case .deleteSecret(let n): "Delete secret \(n)?"
        case .toggleWorkersDev(let on): on ? "Turn on workers.dev for \(worker)?" : "Turn off workers.dev for \(worker)?"
        case .removeBinding(let n): "Remove binding \(n)?"
        }
    }

    func message(worker: String) -> String {
        switch self {
        case .removeVar(let n): "\(worker) will stop receiving \(n). Code that reads it gets undefined."
        case .deleteSecret(let n): "\(worker) will lose the secret \(n). This can't be undone, and its value can't be read back."
        case .toggleWorkersDev(let on): on ? "\(worker) becomes reachable on its workers.dev address." : "\(worker) stops answering on its workers.dev address."
        case .removeBinding(let n): "\(worker) will lose its \(n) binding. Code that uses it will fail until you add it back."
        }
    }

    var confirmLabel: String {
        switch self {
        case .removeVar, .removeBinding: "Remove"
        case .deleteSecret: "Delete secret"
        case .toggleWorkersDev(let on): on ? "Turn on" : "Turn off"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .toggleWorkersDev(let on): !on
        default: true
        }
    }
}
