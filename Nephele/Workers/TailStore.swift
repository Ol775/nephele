import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class TailStore {
    enum State: Equatable { case idle, connecting, live, stopped(String?) }
    static let cap = 500

    private(set) var state: State = .idle
    private(set) var events: [TailEvent] = []
    private(set) var samplingNotice = false
    var errorsOnly = false
    var visibleEvents: [TailEvent] { errorsOnly ? events.filter(\.isError) : events }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let script: String
    @ObservationIgnored private let openSocket: @Sendable (URL) -> AsyncStream<Data>
    @ObservationIgnored private var active: TailSession?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(session: Session, script: String, openSocket: @escaping @Sendable (URL) -> AsyncStream<Data> = TailStore.webSocket) {
        self.session = session
        self.script = script
        self.openSocket = openSocket
    }

    /// Starts the tail in the background.
    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Starts the tail and returns when the socket closes or the tail is stopped.
    func run() async {
        guard let client = session.client, let account = session.selectedAccountID else { return }
        events = []
        samplingNotice = false
        state = .connecting
        do {
            let tail = try await client.startTail(accountID: account, script: script)
            active = tail
            state = .live
            for await data in openSocket(tail.url) {
                if let event = TailEvent.parse(data) {
                    events.append(event)
                    if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
                } else if let text = String(data: data, encoding: .utf8)?.lowercased(), text.contains("sampl") {
                    samplingNotice = true
                }
            }
            if state == .live { state = .stopped(nil) }
        } catch let error as CloudflareError {
            session.handle(error)
            state = .stopped(Self.friendly(error))
        } catch { state = .stopped("Couldn't start the log tail.") }
        task = nil
    }

    func stop() async {
        task?.cancel()
        task = nil
        if let tail = active, let client = session.client, let account = session.selectedAccountID {
            active = nil
            try? await client.stopTail(accountID: account, script: script, id: tail.id)
        }
        state = .stopped(nil)
    }

    func clear() { events = [] }

    private static func friendly(_ error: CloudflareError) -> String {
        switch error {
        case .permissionDenied: return "This token can't tail logs. Add Workers Tail Read to it in Cloudflare, then try again."
        case .api(_, let message) where message.lowercased().contains("too many") || message.lowercased().contains("limit"):
            return "Too many people are watching this Worker's logs. Try again shortly."
        default: return error.errorDescription ?? "Couldn't start the log tail."
        }
    }

    nonisolated static func webSocket(_ url: URL) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let socket = URLSession.shared.webSocketTask(with: url, protocols: ["trace-v1"])
            socket.resume()
            let reader = Task {
                while !Task.isCancelled {
                    do {
                        switch try await socket.receive() {
                        case .string(let s): continuation.yield(Data(s.utf8))
                        case .data(let d): continuation.yield(d)
                        @unknown default: break
                        }
                    } catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel(); socket.cancel(with: .goingAway, reason: nil) }
        }
    }
}
