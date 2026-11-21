import SwiftUI
import CloudflareKit

struct WorkersView: View {
    @Environment(WorkersStore.self) private var workers
    @Environment(Session.self) private var session
    @State private var query = ""
    @State private var creating = false
    @State private var path: [WorkerScript] = []

    var body: some View {
        NavigationStack(path: $path) {
            LoadStateView(state: workers.workers, permission: "Workers Scripts Read", isEmpty: { $0.isEmpty },
                          emptyTitle: "No Workers yet", emptyMessage: "Create one from a template, or deploy with Wrangler.", emptySymbol: "curlybraces",
                          retry: { Task { await workers.load(force: true) } }) { all in
                let shown = all.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
                if shown.isEmpty {
                    EmptyStateView(title: "No Workers match", message: "Check the spelling, or clear the filter.", symbol: "magnifyingglass")
                } else {
                    List(shown) { script in
                        NavigationLink(value: script) { WorkerRow(script: script) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Filter Workers")
            .toolbar {
                ToolbarItem { Button("New Worker", systemImage: "plus") { creating = true } }
                ToolbarItem { Button("Refresh", systemImage: "arrow.clockwise") { Task { await workers.load(force: true) } } }
            }
            .sheet(isPresented: $creating) { NewWorkerSheet(workers: workers) { path = [$0] } }
            .navigationDestination(for: WorkerScript.self) { WorkerDetailView(script: $0) }
        }
        .task { await workers.load() }
        .onChange(of: session.identityEpoch) { path = [] }
    }
}

struct WorkerRow: View {
    let script: WorkerScript
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "curlybraces").frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.tint)
            Text(script.id).fontWeight(.medium)
            Spacer()
            ForEach(script.handlers ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            if let modified = script.modifiedOn {
                Text("Updated \(modified.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary).frame(width: 170, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
    }
}
