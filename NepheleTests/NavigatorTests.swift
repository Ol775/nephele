import Testing
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
