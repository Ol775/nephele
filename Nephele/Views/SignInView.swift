import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.nepheleTheme) private var theme
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud").font(.system(size: 44, weight: theme.iconWeight)).foregroundStyle(theme.accent)
            Text("Connect your Cloudflare account").font(.title2.bold())
            Text("Paste an API token. Start with read-only access: Zone Read, DNS Read, Notifications Read and Account Analytics Read. Nephele keeps it in your Keychain and sends it only to Cloudflare.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            SecureField("API token", text: $token).textFieldStyle(.roundedBorder).frame(maxWidth: 380).onSubmit(submit)
            if let text = message ?? session.signInError {
                Text(text).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            HStack(spacing: 16) {
                Button("Verify and save", action: submit).buttonStyle(.borderedProminent)
                Link("Create a token", destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
            }
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
