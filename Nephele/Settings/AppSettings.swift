import Foundation

enum Route: String, Codable, CaseIterable, Sendable { case overview, domains, workers, storage, alerts, usage, appearance, settings }
enum ThemeChoice: String, Codable, CaseIterable, Sendable { case system, light, dark }
enum Density: String, Codable, CaseIterable, Sendable { case compact, comfortable }
enum FontChoice: String, Codable, CaseIterable, Sendable { case system, rounded, serif, mono }

struct NavEntry: Codable, Equatable, Sendable, Identifiable {
    var id: Route
    var visible: Bool
}

struct OverviewSections: Codable, Equatable, Sendable {
    var stats = true, chart = true, alerts = true, domains = true
    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        stats = c.value(.stats, true); chart = c.value(.chart, true); alerts = c.value(.alerts, true); domains = c.value(.domains, true)
    }
    private enum Keys: String, CodingKey { case stats, chart, alerts, domains }
}

struct NotificationPrefs: Codable, Equatable, Sendable {
    var cert = true, origin = true, usage = true, deploy = true, security = false
    var pollMinutes = 5
    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        cert = c.value(.cert, true); origin = c.value(.origin, true); usage = c.value(.usage, true)
        deploy = c.value(.deploy, true); security = c.value(.security, false); pollMinutes = c.value(.pollMinutes, 5)
    }
    private enum Keys: String, CodingKey { case cert, origin, usage, deploy, security, pollMinutes }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let defaultAccent = "#F6821F"
    static let pollChoices = [1, 5, 15, 30]

    var theme: ThemeChoice = .system
    var accentHex = AppSettings.defaultAccent
    var density: Density = .comfortable
    var radius = 10.0
    var fontSize = 14.0
    var fontDesign: FontChoice = .system
    var iconWeight = 1.8
    var tintSidebar = true
    var sidebarIcons = false
    var highContrast = false
    var reduceMotion = false
    var landing: Route = .overview
    var nav: [NavEntry] = Route.allCases.map { NavEntry(id: $0, visible: true) }
    var overview = OverviewSections()
    var notifications = NotificationPrefs()
    var openAtLogin = false
    var showMenuBar = true

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        theme = c.value(.theme, .system); accentHex = c.value(.accentHex, Self.defaultAccent)
        density = c.value(.density, .comfortable); radius = c.value(.radius, 10); fontSize = c.value(.fontSize, 14)
        fontDesign = c.value(.fontDesign, .system); iconWeight = c.value(.iconWeight, 1.8)
        tintSidebar = c.value(.tintSidebar, true); sidebarIcons = c.value(.sidebarIcons, false)
        highContrast = c.value(.highContrast, false); reduceMotion = c.value(.reduceMotion, false)
        landing = c.value(.landing, .overview)
        if let lossy = try? c.decodeIfPresent([Lossy<NavEntry>].self, forKey: .nav) { nav = lossy.compactMap(\.value) }
        overview = c.value(.overview, OverviewSections()); notifications = c.value(.notifications, NotificationPrefs())
        openAtLogin = c.value(.openAtLogin, false); showMenuBar = c.value(.showMenuBar, true)
        self = normalized()
    }

    private enum Keys: String, CodingKey {
        case theme, accentHex, density, radius, fontSize, fontDesign, iconWeight, tintSidebar, sidebarIcons
        case highContrast, reduceMotion, landing, nav, overview, notifications, openAtLogin, showMenuBar
    }

    /// Clamps ranges, repairs the nav list and keeps Appearance and Settings reachable.
    func normalized() -> AppSettings {
        var s = self
        s.radius = min(max(radius, 0), 20)
        s.fontSize = min(max(fontSize, 12), 18)
        s.iconWeight = min(max(iconWeight, 1.2), 2.6)
        if accentHex.wholeMatch(of: /#[0-9A-Fa-f]{6}/) == nil { s.accentHex = Self.defaultAccent } else { s.accentHex = accentHex.uppercased() }
        s.notifications.pollMinutes = Self.pollChoices.min { abs($0 - notifications.pollMinutes) < abs($1 - notifications.pollMinutes) } ?? 5
        var seen = Set<Route>()
        var list = nav.filter { seen.insert($0.id).inserted }
        for route in Route.allCases where !seen.contains(route) { list.append(NavEntry(id: route, visible: true)) }
        for i in list.indices where list[i].id == .appearance || list[i].id == .settings { list[i].visible = true }
        s.nav = list
        if !list.contains(where: { $0.id == s.landing && $0.visible }) { s.landing = .overview }
        return s
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T { (try? decodeIfPresent(T.self, forKey: key)) ?? fallback }
}
