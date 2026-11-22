import Observation
import CloudflareKit

/// Shared sidebar selection so menu commands and shortcuts can navigate.
@MainActor @Observable
final class Navigator {
    var selection: Route?
    private(set) var searchRequest = 0
    /// Deep link used by demo screenshots: open a domain, optionally straight onto one of its sub-screens.
    var openZone: Zone?
    var zoneScreen: String?

    func openSettings() { selection = .settings }

    func searchDomains() {
        selection = .domains
        searchRequest += 1
    }
}
