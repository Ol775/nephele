import SwiftUI
import CloudflareKit

struct PagesView: View {
    @Environment(PagesStore.self) private var pages
    @Environment(Session.self) private var session
    @State private var deleting: PagesProject?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                LoadStateView(state: pages.projects, permission: "Cloudflare Pages Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No Pages projects", emptyMessage: "Create a project in the Cloudflare dashboard; it appears here.", emptySymbol: "doc.richtext",
                              retry: { Task { await pages.load() } }) { list in
                    List(list, selection: Binding(get: { pages.selected?.id }, set: { id in Task { await pages.select(list.first { $0.id == id }) } })) { p in
                        VStack(alignment: .leading) {
                            Text(p.name)
                            if let d = p.domains?.first { Text(d).font(.footnote).foregroundStyle(.secondary) }
                        }.tag(p.id).contextMenu { Button("Delete\u{2026}", role: .destructive) { pages.clearError(); deleting = p }.disabled(!pages.canWrite) }
                    }
                }
                Divider()
                HStack {
                    if let p = pages.selected { Button("Delete", systemImage: "trash") { pages.clearError(); deleting = p }.disabled(!pages.canWrite) }
                    Spacer()
                }.padding(8)
            }.frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            detail.frame(minWidth: 360)
        }
        .task(id: session.identityEpoch) { await pages.load() }
        .onChange(of: session.identityEpoch) { deleting = nil }
        .sheet(item: $deleting) { p in
            TypedConfirmSheet(title: "Delete \(p.name)?", message: "This deletes the project and all its deployments. It can't be undone. Type its name to confirm.",
                              name: p.name, buttonLabel: "Delete project", error: pages.formError,
                              onConfirm: { await pages.deleteProject(p, typedName: $0) }, onDone: { if pages.formError == nil { deleting = nil } })
        }
        .confirmationDialog(pages.confirm.pending?.title(project: pages.selected?.name ?? "") ?? "",
                            isPresented: Binding(get: { pages.confirm.pending != nil }, set: { if !$0 { pages.confirm.dialogDismissed() } }),
                            presenting: pages.confirm.pending) { change in
            Button(change.button, role: change.isRetry ? nil : .destructive) { Task { await pages.confirmChange(change) } }
            Button("Cancel", role: .cancel) { pages.confirm.cancel() }
        } message: { change in Text(change.message(project: pages.selected?.name ?? "")) }
    }

    @ViewBuilder private var detail: some View {
        if let p = pages.selected {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.title2)
                    Text([p.subdomain, p.productionBranch.map { "Branch \($0)" }].compactMap { $0 }.joined(separator: " \u{00B7} ")).foregroundStyle(.secondary)
                    if let domains = p.domains, domains.count > 1 { Text(domains.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !pages.canWrite { Label("Needs a token with Cloudflare Pages Edit", systemImage: "lock").foregroundStyle(.secondary) }
                    else if let e = pages.formError, pages.formErrorProject == p.name, deleting == nil { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }.padding()
                Divider()
                LoadStateView(state: pages.deployments, permission: "Cloudflare Pages Read", isEmpty: { $0.isEmpty },
                              emptyTitle: "No deployments", emptyMessage: "Push to the project's branch to create one.", emptySymbol: "shippingbox",
                              retry: { Task { await pages.loadDeployments() } }) { list in
                    List(list) { d in deploymentRow(d) }
                }
            }
        } else {
            ContentUnavailableView("Pick a project", systemImage: "doc.richtext", description: Text("Its deployments appear here."))
        }
    }

    @ViewBuilder private func deploymentRow(_ d: PagesDeployment) -> some View {
        HStack {
            StatusDot(kind: d.latestStage?.status == "success" ? .ok : (d.latestStage?.status == "failure" ? .bad : .warning))
            VStack(alignment: .leading) {
                Text(d.trigger?.commitMessage ?? d.shortId ?? d.id).lineLimit(1)
                Text([d.environment?.capitalized, d.trigger?.branch, d.latestStage?.status, d.createdOn.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Actions", systemImage: "ellipsis.circle") {
                let status = d.latestStage?.status
                if status != "active" && status != "idle" { Button("Retry") { pages.request(.retry(d)) } }
                if !pages.isLive(d) {
                    if d.environment == "production", d.latestStage?.name == "deploy", status == "success" { Button("Roll back to this") { pages.request(.rollback(d)) } }
                    Button("Delete", role: .destructive) { pages.request(.delete(d)) }
                } else { Text("Live now") }
            }.accessibilityLabel("Actions for \(d.shortId ?? d.id)").menuStyle(.borderlessButton).labelStyle(.iconOnly).fixedSize().disabled(!pages.canWrite)
        }
    }
}
