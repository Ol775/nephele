import SwiftUI
import CloudflareKit

struct WorkerCodeView: View {
    @Bindable var store: WorkerStore
    @Environment(\.nepheleTheme) private var theme
    @State private var asking = false
    @State private var message = ""
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            LoadStateView(state: store.code, permission: "Workers Scripts Read", retry: { Task { await store.loadCode() } }) { _ in
                VStack(spacing: 0) {
                    header
                    Divider()
                    if let reason = store.readOnlyReason {
                        ContentUnavailableView("Can't edit this module", systemImage: "doc.badge.gearshape", description: Text(reason))
                    } else {
                        CodeEditor(text: $store.draft, fontSize: theme.fontSize)
                            .padding(8)
                            .accessibilityLabel("Worker code")
                    }
                }
            }
        }
        .task { await store.loadCode() }
        .sheet(isPresented: $asking) { saveSheet }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let reason = store.formError { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(2) }
            else if store.hasUnsavedChanges { Label("Unsaved changes", systemImage: "circle.fill").foregroundStyle(.orange).labelStyle(.titleAndIcon) }
            else if let id = store.lastSavedVersionID { Text("Saved as version \(String(id.prefix(8))). Deploy it from Versions.").foregroundStyle(.secondary) }
            else { Text("Saving creates a new version. It isn't live until you deploy it.").foregroundStyle(.secondary) }
            if !store.extraModules.isEmpty {
                Text("Also in this Worker: \(store.extraModules.map(\.name).joined(separator: ", ")) (sent unchanged)")
                    .font(.footnote).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if !store.canWrite { Label("Needs Workers Scripts Edit", systemImage: "lock").foregroundStyle(.secondary) }
            Button("Revert") { store.draft = store.loadedText ?? "" }.disabled(!store.hasUnsavedChanges)
            Button("Save as new version\u{2026}") { message = ""; asking = true }
                .disabled(!store.hasUnsavedChanges || !store.canWrite || store.readOnlyReason != nil)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(10)
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save as a new version").font(.headline)
            Text("This creates a new version of \(store.script.id). It isn't live until you deploy it from Versions.").foregroundStyle(.secondary)
            TextField("What changed?", text: $message).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { asking = false }
                Button("Save version") {
                    saving = true
                    Task { await store.saveVersion(message: message); saving = false; if store.formError == nil { asking = false } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .padding(20).frame(width: 420)
    }
}
