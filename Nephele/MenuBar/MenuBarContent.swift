import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AlertsStore.self) private var alerts
    @Environment(DomainsStore.self) private var domains
    @Environment(Navigator.self) private var navigator
    @Environment(Session.self) private var session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if session.state == .ready {
            let open = alerts.openCount
            Text(open == 0 ? "No open alerts" : "\(open) open alert\(open == 1 ? "" : "s")")
            Divider()
            if let zones = domains.zones.value, !zones.isEmpty {
                ForEach(zones.prefix(5)) { zone in
                    Text("\(zone.isActive ? "\u{25CF}" : "\u{25CB}") \(zone.name)")
                }
                Divider()
            }
        } else {
            Text("Not signed in")
            Divider()
        }
        Button("Open Nephele") { openWindow(id: "main"); NSApp.activate() }
        Button("Settings\u{2026}") { navigator.openSettings(); NSApp.activate() }
        Divider()
        Button("Quit Nephele") { NSApp.terminate(nil) }
    }
}
