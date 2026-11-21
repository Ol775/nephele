import SwiftUI
import CloudflareKit

struct WorkerVersionsView: View {
    let store: WorkerStore

    var body: some View {
        VStack(spacing: 0) {
            if !store.canWrite { Label("Needs a token with Workers Scripts Edit", systemImage: "lock").foregroundStyle(.secondary).padding(.top, 8) }
            if let error = store.formError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(.top, 8) }
            LoadStateView(state: store.versions, permission: "Workers Scripts Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No versions yet", emptyMessage: "Save code from the Code tab to create the first version.", emptySymbol: "clock.arrow.circlepath",
                          retry: { Task { await store.loadVersions() } }) { versions in
                List(versions) { v in
                    HStack(spacing: 12) {
                        StatusDot(kind: store.isLive(v) ? .ok : .muted)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(v.number.map { "Version \($0)" } ?? "Version").fontWeight(.medium)
                                Text(String(v.id.prefix(8))).monospaced().font(.footnote).foregroundStyle(.secondary)
                                if store.isLive(v) { Text("Live").font(.footnote).foregroundStyle(.green) }
                            }
                            if let message = v.message { Text(message).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if let date = v.createdOn { Text(date.formatted(.relative(presentation: .named))).foregroundStyle(.secondary) }
                        Button(isRollback(v) ? "Roll back" : "Deploy") { store.requestDeploy(v) }
                            .disabled(store.isLive(v) || !store.canWrite)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .task { await store.loadVersions() }
        .confirmationDialog(store.confirm.pending?.title(worker: store.script.id) ?? "",
                            isPresented: Binding(get: { store.confirm.pending != nil }, set: { if !$0 { store.confirm.dialogDismissed() } }),
                            presenting: store.confirm.pending) { change in
            Button(change.confirmLabel, role: change.isDestructive ? .destructive : nil) { Task { await store.confirmChange(change) } }
            Button("Cancel", role: .cancel) { store.confirm.cancel() }
        } message: { change in Text(change.message(worker: store.script.id)) }
    }

    private func isRollback(_ v: WorkerVersion) -> Bool {
        guard let live = store.versions.value?.first(where: { store.isLive($0) }), let a = v.number, let b = live.number else { return false }
        return a < b
    }
}
