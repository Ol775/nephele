import SwiftUI
import AppKit

struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.nepheleTheme) private var theme
    @State private var token = ""
    @State private var message: String?
    @State private var access = TokenAccess.readOnly

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage()).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            Text("Connect your Cloudflare account").font(.title2.bold())
            Text("Paste an API token (it starts with cfut_ or cfat_). Nephele keeps it in your Keychain and sends it only to Cloudflare.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            VStack(spacing: 6) {
                Picker("Access for a new token", selection: $access) {
                    ForEach(TokenAccess.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Text(access.summary).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            SecureField("API token", text: $token).textFieldStyle(.roundedBorder).frame(maxWidth: 380).onSubmit(submit)
            if let text = message ?? session.signInError {
                Text(text).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            HStack(spacing: 16) {
                if session.canRetryRestore { Button("Try again") { Task { await session.restore() } } }
                Button("Verify and save", action: submit).buttonStyle(.borderedProminent)
                Link("Create a \(access.title.lowercased()) token", destination: access.createURL)
            }
            Text(access.byHand).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            if session.state == .verifying { ProgressView().controlSize(.small) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        message = nil
        Task {
            do { try await session.signIn(token: token); token = "" }
            catch { message = (error as? LocalizedError)?.errorDescription ?? "Couldn't verify that token." }
        }
    }
}
