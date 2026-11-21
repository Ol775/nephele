import Foundation
import CloudflareKit

/// Polls alert history while signed in and posts one notification per new event.
@MainActor
final class AlertPoller {
    private let store: AlertsStore
    private let session: Session
    private let settings: SettingsStore
    private let notifier: any Notifier
    private let defaults: UserDefaults
    private var deduper: AlertDeduper
    private var task: Task<Void, Never>?
    private static let key = "nephele.alerts.deduper"

    init(store: AlertsStore, session: Session, settings: SettingsStore, notifier: any Notifier = SystemNotifier(), defaults: UserDefaults = .standard) {
        self.store = store
        self.session = session
        self.settings = settings
        self.notifier = notifier
        self.defaults = defaults
        deduper = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(AlertDeduper.self, from: $0) } ?? AlertDeduper()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                let minutes = self?.settings.settings.notifications.pollMinutes ?? 5
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func pollOnce() async {
        guard session.state == .ready, let events = await store.fetchEvents() else { return }
        guard deduper.isPrimed else {
            deduper.prime(events)
            persist()
            return
        }
        let fresh = deduper.newEvents(events)
        persist()
        let prefs = settings.settings.notifications
        for event in fresh where AlertCategory.of(alertType: event.alertType)?.isEnabled(in: prefs) ?? true {
            await notifier.post(title: event.name, body: event.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(deduper) { defaults.set(data, forKey: Self.key) }
    }
}
