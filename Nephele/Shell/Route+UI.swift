import Foundation

extension Route {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .domains: "Domains"
        case .workers: "Workers"
        case .storage: "Storage"
        case .zeroTrust: "Zero Trust"
        case .turnstile: "Turnstile"
        case .pages: "Pages"
        case .alerts: "Alerts"
        case .usage: "Usage"
        case .appearance: "Appearance"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .domains: "globe"
        case .workers: "curlybraces"
        case .storage: "externaldrive"
        case .zeroTrust: "lock.shield"
        case .turnstile: "checkmark.shield"
        case .pages: "doc.richtext"
        case .alerts: "bell"
        case .usage: "chart.bar"
        case .appearance: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

extension AppSettings {
    var visibleRoutes: [Route] { nav.filter(\.visible).map(\.id) }
}
