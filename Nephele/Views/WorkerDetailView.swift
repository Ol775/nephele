import SwiftUI
import CloudflareKit

enum WorkerTab: String, CaseIterable, Identifiable {
    case overview = "Overview", settings = "Settings", triggers = "Triggers", versions = "Versions", code = "Code", logs = "Logs"
    var id: String { rawValue }
}

struct WorkerDetailView: View {
    @Environment(WorkersStore.self) private var workers
    let script: WorkerScript
    @State private var tab = WorkerTab.overview
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    private var store: WorkerStore { workers.detail(for: script) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(WorkerTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding()
            Divider()
            Group {
                switch tab {
                case .overview: WorkerOverviewView(store: store)
                case .settings: WorkerSettingsView(store: store)
                case .triggers: WorkerTriggersView(store: store)
                case .versions: WorkerVersionsView(store: store)
                case .code: WorkerCodeView(store: store)
                case .logs: WorkerLogsView(script: script.id, session: store.session)
                default: ContentUnavailableView(tab.rawValue, systemImage: "hammer", description: Text("Coming next."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(store.script.id)
        .toolbar { ToolbarItem { Button("Delete Worker\u{2026}", systemImage: "trash", role: .destructive) { deleting = true } } }
        .sheet(isPresented: $deleting) { DeleteWorkerSheet(workers: workers, script: script) { dismiss() } }
        .task { await store.load() }
    }
}

struct WorkerOverviewView: View {
    let store: WorkerStore

    var body: some View {
        Form {
            Section("Worker") {
                LabeledContent("Name", value: store.script.id)
                if let date = store.script.compatibilityDate { LabeledContent("Compatibility date", value: date) }
                if let modified = store.script.modifiedOn { LabeledContent("Last updated", value: modified.formatted(date: .abbreviated, time: .shortened)) }
            }
            Section("Live deployment") {
                LoadStateView(state: store.latestDeployment, permission: "Workers Scripts Read",
                              retry: { Task { await store.load() } }) { deployment in
                    if let deployment {
                        LabeledContent("Version", value: String(deployment.versions.first?.versionId.prefix(8) ?? "none")).monospaced()
                        LabeledContent("Deployed", value: deployment.createdOn.formatted(date: .abbreviated, time: .shortened))
                        if let message = deployment.message { LabeledContent("Message", value: message) }
                    } else {
                        Text("Nothing is deployed yet.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
