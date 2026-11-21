import SwiftUI

@main
struct NepheleApp: App {
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(settings)
                .frame(minWidth: 860, minHeight: 560)
        }
    }
}
