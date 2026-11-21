import SwiftUI
import Observation

enum SettingsError: Error, Equatable, LocalizedError {
    case invalid
    var errorDescription: String? { "That isn't valid settings JSON." }
}

@MainActor @Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "nephele.settings") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        settings = next.normalized()
        persist()
    }

    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(settings)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    func importJSON(_ text: String) throws {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { throw SettingsError.invalid }
        settings = decoded
        persist()
    }

    func reset() {
        settings = AppSettings()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
