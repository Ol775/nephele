import Observation

/// Shared sidebar selection so menu commands and shortcuts can navigate.
@MainActor @Observable
final class Navigator {
    var selection: Route?
    private(set) var searchRequest = 0

    func openSettings() { selection = .settings }

    func searchDomains() {
        selection = .domains
        searchRequest += 1
    }
}
