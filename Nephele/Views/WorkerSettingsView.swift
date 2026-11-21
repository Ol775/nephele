import SwiftUI
import CloudflareKit

struct WorkerSettingsView: View {
    let store: WorkerStore
    @State private var varName = ""
    @State private var varValue = ""
    @State private var secretName = ""
    @State private var secretValue = ""
    @State private var compatDate = ""

    private var denied: String { "Needs a token with Workers Scripts Edit" }

    var body: some View {
        Form {
            if !store.canWrite {
                Section { Label(denied, systemImage: "lock").foregroundStyle(.secondary) }
            }
            if let error = store.formError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section("Runtime") {
                LoadStateView(state: store.settings, permission: "Workers Scripts Read", retry: { Task { await store.loadSettings() } }) { s in
                    HStack {
                        TextField("Compatibility date", text: $compatDate, prompt: Text("2026-10-01"))
                        Button("Save") { Task { await store.saveSettings(WorkerSettingsChange(compatibilityDate: compatDate)) } }
                            .disabled(!store.canWrite || compatDate.isEmpty || compatDate == s.compatibilityDate)
                    }
                    .onAppear { compatDate = s.compatibilityDate ?? "" }
                    Toggle("nodejs_compat", isOn: flag(s))
                    Toggle("Observability (Workers Logs)", isOn: Binding(
                        get: { s.observabilityEnabled },
                        set: { v in Task { await store.saveSettings(WorkerSettingsChange(observabilityEnabled: v)) } }))
                    .disabled(!store.canWrite)
                    Toggle("Reachable on workers.dev", isOn: Binding(
                        get: { store.workersDev ?? false },
                        set: { store.requestChange(.toggleWorkersDev($0)) }))
                    .disabled(!store.canWrite || store.workersDev == nil)
                }
            }
            Section("Variables") {
                if let vars = store.settings.value?.plainVars {
                    ForEach(vars) { v in
                        LabeledContent(v.name) {
                            HStack {
                                Text(v.text ?? "").foregroundStyle(.secondary).lineLimit(1)
                                Button(role: .destructive) { store.requestChange(.removeVar(v.name)) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).disabled(!store.canWrite).accessibilityLabel("Remove variable \(v.name)")
                            }
                        }
                    }
                    if vars.isEmpty { Text("No variables.").foregroundStyle(.secondary) }
                }
                HStack {
                    TextField("Name", text: $varName)
                    TextField("Value", text: $varValue)
                    Button("Add") { Task { await store.setVar(name: varName, value: varValue); if store.formError == nil { varName = ""; varValue = "" } } }
                        .disabled(!store.canWrite || varName.isEmpty)
                }
            }
            Section("Secrets") {
                LoadStateView(state: store.secretNames, permission: "Workers Scripts Read", retry: { Task { await store.loadSettings() } }) { names in
                    ForEach(names, id: \.self) { n in
                        LabeledContent(n) {
                            HStack {
                                Text("Hidden").foregroundStyle(.tertiary)
                                Button(role: .destructive) { store.requestChange(.deleteSecret(n)) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).disabled(!store.canWrite).accessibilityLabel("Delete secret \(n)")
                            }
                        }
                    }
                    if names.isEmpty { Text("No secrets.").foregroundStyle(.secondary) }
                }
                HStack {
                    TextField("Name", text: $secretName)
                    SecureField("Value", text: $secretValue)
                    Button("Set secret") {
                        let (n, v) = (secretName, secretValue)
                        secretValue = ""
                        Task { await store.setSecret(name: n, value: v); if store.formError == nil { secretName = "" } }
                    }
                    .disabled(!store.canWrite || secretName.isEmpty || secretValue.isEmpty)
                }
                Text("Secret values are write-only. Cloudflare never shows them again.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Bindings") {
                let others = (store.settings.value?.bindings ?? []).filter { $0.type != "plain_text" && !$0.isSecret }
                ForEach(others) { b in
                    LabeledContent(b.name) {
                        HStack {
                            Text(b.type).foregroundStyle(.secondary)
                            Button(role: .destructive) { store.requestChange(.removeBinding(b.name)) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).disabled(!store.canWrite).accessibilityLabel("Remove binding \(b.name)")
                        }
                    }
                }
                if others.isEmpty { Text("No other bindings.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .task { await store.loadSettings() }
        .confirmationDialog(store.confirm.pending?.title(worker: store.script.id) ?? "",
                            isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }),
                            presenting: store.confirm.pending) { change in
            Button(change.confirmLabel, role: change.isDestructive ? .destructive : nil) { Task { await store.confirmChange(change) } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { change in Text(change.message(worker: store.script.id)) }
    }

    private func flag(_ s: WorkerSettings) -> Binding<Bool> {
        Binding(
            get: { s.compatibilityFlags.contains("nodejs_compat") },
            set: { on in
                var flags = s.compatibilityFlags.filter { $0 != "nodejs_compat" }
                if on { flags.append("nodejs_compat") }
                Task { await store.saveSettings(WorkerSettingsChange(compatibilityFlags: flags)) }
            })
        .disabledWhen(!store.canWrite)
    }
}

private extension Binding where Value == Bool {
    /// Ignores changes while writes are off.
    func disabledWhen(_ off: Bool) -> Binding<Bool> {
        off ? Binding(get: { wrappedValue }, set: { _ in }) : self
    }
}
