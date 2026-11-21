import SwiftUI
import CloudflareKit

struct NewWorkerSheet: View {
    let workers: WorkersStore
    var created: (WorkerScript) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template = WorkerTemplate.hello
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Worker").font(.headline)
            TextField("Name", text: $name, prompt: Text("my-worker")).textFieldStyle(.roundedBorder)
            if !name.isEmpty && !validWorkerName(name) {
                Text(WorkerValidationError.invalidName.errorDescription ?? "").font(.footnote).foregroundStyle(.red)
            }
            Picker("Template", selection: $template) { ForEach(WorkerTemplate.allCases) { Text($0.title).tag($0) } }
            if let cron = template.cron { Text("Add a cron trigger such as \(cron) from Triggers after you deploy it.").font(.footnote).foregroundStyle(.secondary) }
            Text("This creates the Worker and saves a first version. It isn't live until you deploy it from Versions.").font(.footnote).foregroundStyle(.secondary)
            if let error = workers.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create version") {
                    working = true
                    Task {
                        if let script = await workers.create(name: name, template: template) { dismiss(); created(script) }
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(!validWorkerName(name) || working)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { workers.formError = nil }
    }
}

struct DeleteWorkerSheet: View {
    let workers: WorkersStore
    let script: WorkerScript
    var deleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete \(script.id)?").font(.headline)
            Text("This deletes the Worker with all its versions and deployments. It can't be undone. Type its name to confirm.").foregroundStyle(.secondary)
            TextField(script.id, text: $typed).textFieldStyle(.roundedBorder).accessibilityLabel("Type the Worker name to confirm")
            if let error = workers.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Delete Worker", role: .destructive) {
                    working = true
                    Task { await workers.delete(script, typedName: typed); working = false; if workers.formError == nil { dismiss(); deleted() } }
                }
                .disabled(typed != script.id || working)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { workers.formError = nil }
    }
}
