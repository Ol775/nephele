import SwiftUI
import ServiceManagement

extension Notification.Name { static let nepheleClearCache = Notification.Name("nephele.clearCache") }

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(SettingsStore.self) private var store
    @State private var newToken = ""
    @State private var tokenMessage: String?
    @State private var confirmRemove = false
    @State private var cacheCleared = false

    var body: some View {
        @Bindable var session = session
        Form {
            Section("Account and API token") {
                if session.state == .ready {
                    Picker("Account", selection: $session.selectedAccountID) {
                        ForEach(session.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    LabeledContent("Token") {
                        HStack { Text("\u{2022}\u{2022}\u{2022}\u{2022} \(session.tokenHint)").monospaced(); Button("Remove") { confirmRemove = true } }
                    }
                    LabeledContent("Permissions") { Text(session.missingPermissions.isEmpty ? "All present" : "\(session.missingPermissions.count) missing").foregroundStyle(.secondary) }
                    ForEach(session.permissions) { p in
                        HStack { StatusDot(kind: p.granted ? .ok : .warning); Text(p.name); Spacer(); Text(p.granted ? "Granted" : "Missing").foregroundStyle(.secondary) }
                    }
                    Text("Screens that need a missing permission show a prompt instead of data. Edit rights are not checked until you make a change.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Add an API token to continue.").foregroundStyle(.secondary)
                }
                SecureField("Paste a new API token", text: $newToken)
                HStack {
                    Button("Verify and save") { replaceToken() }
                    if let tokenMessage { Text(tokenMessage).foregroundStyle(.secondary) }
                }
            }
            Section("Notifications") {
                Toggle("Certificates expiring soon", isOn: store.binding(\.notifications.cert))
                Toggle("Origin errors and spikes", isOn: store.binding(\.notifications.origin))
                Toggle("Usage near a plan limit", isOn: store.binding(\.notifications.usage))
                Toggle("Worker deploys and failures", isOn: store.binding(\.notifications.deploy))
                Toggle("Security events", isOn: store.binding(\.notifications.security))
                Picker("Check every", selection: store.binding(\.notifications.pollMinutes)) {
                    ForEach(AppSettings.pollChoices, id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
                }
            }
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { store.settings.openAtLogin }, set: { on in
                    store.update { $0.openAtLogin = on }
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                }))
                Toggle("Show the menu bar item", isOn: store.binding(\.showMenuBar))
                Text("Deleting or overwriting anything asks you to confirm first.").foregroundStyle(.secondary)
            }
            Section("Data and privacy") {
                HStack {
                    Button("Clear cache") { NotificationCenter.default.post(name: .nepheleClearCache, object: nil); cacheCleared = true }
                    if cacheCleared { Text("Cache cleared.").foregroundStyle(.secondary) }
                }
                Text("Results are kept in memory for about a minute and never written to disk. Nephele collects no analytics and talks only to the Cloudflare API.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcuts") {
                LabeledContent("Search domains") { Text("\u{2318}K").monospaced() }
                LabeledContent("Open Settings") { Text("\u{2318},").monospaced() }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                LabeledContent("Licence", value: "MIT")
                Text("An independent app, not affiliated with Cloudflare. Cloudflare is a trademark of Cloudflare, Inc.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove the API token?", isPresented: $confirmRemove) {
            Button("Remove token", role: .destructive) { session.signOut() }
        } message: { Text("Nephele stops syncing until you add another token. The token itself stays valid in Cloudflare.") }
    }

    private func replaceToken() {
        tokenMessage = nil
        Task {
            do { try await session.signIn(token: newToken); newToken = ""; tokenMessage = "Token verified." }
            catch { tokenMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't verify that token." }
        }
    }
}
