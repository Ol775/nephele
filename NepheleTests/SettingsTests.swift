import Testing
import Foundation
@testable import Nephele

@MainActor
@Suite struct SettingsTests {
    func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "nephele.tests.\(UUID().uuidString)")! }

    @Test func settingsRoundTripThroughExportImport() throws {
        let a = SettingsStore(defaults: freshDefaults())
        a.update { $0.accentHex = "#2F7DE1"; $0.radius = 14; $0.density = .compact; $0.fontDesign = .rounded; $0.overview.chart = false }
        let b = SettingsStore(defaults: freshDefaults())
        try b.importJSON(a.exportJSON())
        #expect(b.settings == a.settings)
    }

    @Test func importRejectsInvalidJSON() {
        let store = SettingsStore(defaults: freshDefaults())
        let before = store.settings
        #expect(throws: SettingsError.invalid) { try store.importJSON("not json") }
        #expect(throws: SettingsError.invalid) { try store.importJSON("[1,2,3]") }
        #expect(store.settings == before)
    }

    @Test func importAddsMissingNavEntries() throws {
        let store = SettingsStore(defaults: freshDefaults())
        try store.importJSON("{\"nav\":[{\"id\":\"domains\",\"visible\":true}]}")
        #expect(store.settings.nav.map(\.id).first == .domains)
        #expect(Set(store.settings.nav.map(\.id)) == Set(Route.allCases))
        #expect(store.settings.nav.count == Route.allCases.count)
    }

    @Test func importIgnoresUnknownKeysAndFillsDefaults() throws {
        let store = SettingsStore(defaults: freshDefaults())
        try store.importJSON("{\"accentHex\":\"#112233\",\"bogus\":1}")
        #expect(store.settings.accentHex == "#112233")
        #expect(store.settings.radius == AppSettings().radius)
    }

    @Test func appearanceAndSettingsCannotBeHidden() {
        let store = SettingsStore(defaults: freshDefaults())
        store.update { s in for i in s.nav.indices { s.nav[i].visible = false } }
        let visible = Set(store.settings.nav.filter(\.visible).map(\.id))
        #expect(visible == [.appearance, .settings])
    }

    @Test func clampsOutOfRangeValuesAndBadColours() {
        let store = SettingsStore(defaults: freshDefaults())
        store.update { $0.radius = 99; $0.fontSize = 3; $0.accentHex = "orange"; $0.notifications.pollMinutes = 7 }
        #expect(store.settings.radius == 20)
        #expect(store.settings.fontSize == 12)
        #expect(store.settings.accentHex == "#F6821F")
        #expect([1, 5, 15, 30].contains(store.settings.notifications.pollMinutes))
    }

    @Test func settingsPersistAcrossStoreInstances() {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).update { $0.theme = .dark; $0.landing = .usage }
        let again = SettingsStore(defaults: defaults)
        #expect(again.settings.theme == .dark)
        #expect(again.settings.landing == .usage)
    }

    @Test func resetRestoresDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        store.update { $0.theme = .dark }
        store.reset()
        #expect(store.settings == AppSettings())
    }
}
