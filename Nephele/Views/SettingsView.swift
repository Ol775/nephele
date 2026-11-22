import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(SettingsStore.self) private var store
    @Environment(UpdateModel.self) private var updates
    @State private var newToken = ""
    @State private var tokenMessage: String?
    @State private var confirmRemove = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section("Account and API token") {
                if session.state == .ready {
                    Picker("Account", selection: Binding(get: { session.selectedAccountID }, set: { session.selectAccount($0) })) {
                        ForEach(session.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    LabeledContent("Token") {
                        HStack { Text("\u{2022}\u{2022}\u{2022}\u{2022} \(session.tokenHint)").monospaced(); Button("Remove") { confirmRemove = true } }
                    }
                    LabeledContent("Permissions") { Text(session.missingPermissions.isEmpty ? "No errors" : "\(session.missingPermissions.count) missing").foregroundStyle(.secondary) }
                    ForEach(session.permissions) { p in
                        HStack { StatusDot(kind: p.granted ? .ok : .warning); Text(p.name); Spacer(); Text(p.granted ? "No error" : "Missing").foregroundStyle(.secondary) }
                    }
                    Text("Screens that need a missing permission show a prompt instead of data. Edit rights are not checked until you make a change. Cloudflare sometimes sends an empty list instead of an error when a permission is missing, so an empty screen can mean that too.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Storage: Workers KV Storage, D1 and Workers R2 Storage Read to browse; the same Edit permissions to change anything.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Pages: Cloudflare Pages Read to browse projects and deployments; Cloudflare Pages Edit to retry, roll back or delete.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Domain settings: Zone Settings Read to see SSL/TLS, security and caching; Zone Settings Edit to change them; Cache Purge to purge.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Email Routing: Email Routing Rules Read and Email Routing Addresses Read to browse; Email Routing Rules Edit to change. WAF rules: Zone WAF Read and Edit. Turnstile: Turnstile Sites Read and Edit. Gateway: Zero Trust Read and Edit.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Zero Trust: Cloudflare Tunnel, Access: Apps and Policies and Access: Service Tokens Read to browse; Edit permissions (Zero Trust Edit for Gateway) to create or delete.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Workers: Workers Scripts Read to browse; Workers Scripts Edit to change settings, code and deployments; Workers Tail Read for live logs; Workers Routes Read and Edit (per zone) for routes.")
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
                    Button("Clear cache") { session.clearCache(); cacheCleared = true }
                    if cacheCleared { Text("Cache cleared.").foregroundStyle(.secondary) }
                }
                Text("Results are kept in memory for about a minute. Only your settings and which alerts you have seen are saved on this Mac. Nephele collects no analytics and talks only to the Cloudflare API.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcuts") {
                LabeledContent("Search domains") { Text("\u{2318}K").monospaced() }
                LabeledContent("Open Settings") { Text("\u{2318},").monospaced() }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: store.binding(\.autoUpdate))
                updateRow
                Text("Updates come only from this app's GitHub releases and install only if their signature checks out. After an update macOS may ask once to allow Keychain access: choose Always Allow.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Licence", value: "MIT")
                Text("An independent app, not affiliated with Cloudflare. Cloudflare is a trademark of Cloudflare, Inc.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove the API token?", isPresented: $confirmRemove) {
            Button("Remove token", role: .destructive) { session.signOut() }
        } message: { Text("Nephele stops syncing until you add another token. The token itself stays valid in Cloudflare.") }
    }

    @ViewBuilder private var updateRow: some View {
        switch updates.status {
        case .idle: Button("Check for updates") { updates.check() }
        case .checking: HStack { ProgressView().controlSize(.small); Text("Checking\u{2026}").foregroundStyle(.secondary) }
        case .upToDate:
            HStack { Label("Up to date", systemImage: "checkmark.circle").foregroundStyle(.secondary); Spacer(); Button("Check again") { updates.check() } }
        case .available(let info):
            VStack(alignment: .leading, spacing: 6) {
                Text("Version \(info.version) is available").font(.headline)
                ForEach(Array(info.notes.prefix(6).enumerated()), id: \.offset) { Text($0.element).font(.footnote).foregroundStyle(.secondary) }
                HStack {
                    Button("Update now") { updates.install(info) }.buttonStyle(.borderedProminent).disabled(info.dmgURL == nil || info.sigURL == nil)
                    if info.sigURL == nil { Text("This release isn't signed, so it can't be installed automatically.").font(.footnote).foregroundStyle(.secondary) }
                    Link("Release notes", destination: URL(string: "https://github.com/\(Updater.repo)/releases/tag/v\(info.version)")!)
                }
            }
        case .installing(let message, let fraction):
            VStack(alignment: .leading, spacing: 4) { Text(message); ProgressView(value: fraction) }
        case .failed(let message):
            HStack { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red); Spacer(); Button("Try again") { updates.check() } }
        }
    }

    private func replaceToken() {
        tokenMessage = nil
        Task {
            do { try await session.signIn(token: newToken); newToken = ""; tokenMessage = "Token verified." }
            catch { tokenMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't verify that token." }
        }
    }
}
