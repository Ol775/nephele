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
    private var dedupers: [String: AlertDeduper] = [:]
    private var task: Task<Void, Never>?
    private static let keyPrefix = "nephele.alerts.deduper."

    init(store: AlertsStore, session: Session, settings: SettingsStore, notifier: any Notifier = SystemNotifier(), defaults: UserDefaults = .standard) {
        self.store = store
        self.session = session
        self.settings = settings
        self.notifier = notifier
        self.defaults = defaults
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
        guard session.state == .ready, let account = session.selectedAccountID, let events = await store.fetchEvents() else { return }
        var deduper = dedupers[account] ?? loadDeduper(account)
        guard deduper.isPrimed else {
            // First look at this account: remember its history without notifying about it.
            deduper.prime(events)
            save(deduper, for: account)
            return
        }
        let fresh = deduper.newEvents(events)
        save(deduper, for: account)
        let prefs = settings.settings.notifications
        for event in fresh where AlertCategory.of(alertType: event.alertType)?.isEnabled(in: prefs) ?? true {
            await notifier.post(title: event.name, body: event.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    private func loadDeduper(_ account: String) -> AlertDeduper {
        defaults.data(forKey: Self.keyPrefix + account).flatMap { try? JSONDecoder().decode(AlertDeduper.self, from: $0) } ?? AlertDeduper()
    }

    private func save(_ deduper: AlertDeduper, for account: String) {
        dedupers[account] = deduper
        if let data = try? JSONEncoder().encode(deduper) { defaults.set(data, forKey: Self.keyPrefix + account) }
    }
}
