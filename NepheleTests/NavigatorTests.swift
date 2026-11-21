import Testing
import Foundation
@testable import Nephele

@MainActor
@Suite struct NavigatorTests {
    @Test func openSettingsSelectsTheSettingsRoute() {
        let nav = Navigator()
        nav.openSettings()
        #expect(nav.selection == .settings)
    }

    @Test func searchDomainsSelectsDomainsAndBumpsTheRequestCounter() {
        let nav = Navigator()
        let before = nav.searchRequest
        nav.searchDomains()
        #expect(nav.selection == .domains)
        #expect(nav.searchRequest == before + 1)
    }
}

@MainActor
@Suite struct WorkersRouteTests {
    @Test func workersRouteIsVisibleInDefaultNav() {
        #expect(AppSettings().visibleRoutes.contains(.workers))
    }

    @Test func repairAddsWorkersToSavedNavThatLacksIt() throws {
        let saved = #"{"nav":[{"id":"overview","visible":true},{"id":"domains","visible":true},{"id":"settings","visible":true},{"id":"appearance","visible":true}]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        #expect(decoded.normalized().visibleRoutes.contains(.workers))
    }
}
