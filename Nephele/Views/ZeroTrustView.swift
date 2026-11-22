import SwiftUI
import AppKit
import CloudflareKit

enum ZeroTrustTab: String, CaseIterable, Identifiable {
    case tunnels = "Tunnels", apps = "Applications", tokens = "Service tokens"
    var id: String { rawValue }
}

struct ZeroTrustView: View {
    @Environment(ZeroTrustStore.self) private var zt
    @Environment(Session.self) private var session
    @State private var tab = ZeroTrustTab.tunnels
    @State private var deleting: ZeroTrustTarget?
    @State private var creating = false
    @State private var newName = ""
    @State private var duration = "8760h"
    @State private var working = false

    private var section: ZeroTrustSection { tab == .tunnels ? .tunnels : (tab == .apps ? .apps : .tokens) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Section", selection: $tab) { ForEach(ZeroTrustTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
                Spacer()
                if tab != .apps { Button("New", systemImage: "plus") { newName = ""; zt.formError = nil; creating = true }.disabled(!zt.canWrite(section)) }
            }.padding()
            if !zt.canWrite(section) { Label("This token can't change this. Add \(section.editPermission) to it in Cloudflare.", systemImage: "lock").foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8) }
            if let error = zt.formError, deleting == nil, !creating { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(.horizontal).padding(.bottom, 8) }
            Divider()
            Group {
                switch tab {
                case .tunnels: tunnels
                case .apps: apps
                case .tokens: tokens
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: session.identityEpoch) { await zt.loadAll() }
        .onChange(of: session.identityEpoch) { deleting = nil; creating = false }
        .sheet(item: $deleting) { target in
            TypedConfirmSheet(title: "Delete \(target.name)?", message: "This deletes the \(target.kind). It can't be undone. Type its name to confirm.",
                              name: target.name, buttonLabel: "Delete \(target.kind)", error: zt.formError,
                              onConfirm: { await zt.delete(target, typedName: $0) }, onDone: { if zt.formError == nil { deleting = nil } })
        }
        .sheet(isPresented: Binding(get: { creating || zt.newSecret != nil }, set: { if !$0 { creating = false; zt.dismissSecret() } })) {
            if let secret = zt.newSecret {
                SecretSheet(secret: secret) { zt.dismissSecret(); creating = false }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tab == .tunnels ? "New tunnel" : "New service token").font(.headline)
                    TextField("Name", text: $newName).textFieldStyle(.roundedBorder)
                    if tab == .tokens {
                        Picker("Valid for", selection: $duration) { Text("1 year").tag("8760h"); Text("6 months").tag("4380h"); Text("30 days").tag("720h") }
                    }
                    if let e = zt.formError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { creating = false }
                        Button("Create") {
                            working = true
                            Task {
                                if tab == .tunnels { await zt.createTunnel(newName) } else { await zt.createToken(name: newName, duration: duration) }
                                working = false
                                if zt.formError == nil { creating = false }
                            }
                        }.disabled(working || newName.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
                    }
                }.padding(20).frame(width: 400)
            }
        }
    }

    private var tunnels: some View {
        LoadStateView(state: zt.tunnels, permission: "Cloudflare Tunnel Read", isEmpty: { $0.isEmpty },
                      emptyTitle: "No tunnels", emptyMessage: "Create one, then run the connector it gives you in the Cloudflare dashboard.", emptySymbol: "point.3.connected.trianglepath.dotted",
                      retry: { Task { await zt.loadAll() } }) { list in
            List(list) { t in
                HStack {
                    StatusDot(kind: t.status == "healthy" ? .ok : (t.status == "inactive" ? .muted : (t.status == "down" ? .bad : .warning)))
                    VStack(alignment: .leading) {
                        Text(t.name)
                        Text([t.status?.capitalized, t.connections.map { "\($0.count) connection\($0.count == 1 ? "" : "s")" }].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete\u{2026}", role: .destructive) { zt.formError = nil; deleting = .tunnel(t) }.disabled(!zt.canWrite(section))
                }
            }
        }
    }

    private var apps: some View {
        LoadStateView(state: zt.apps, permission: "Access: Apps and Policies Read", isEmpty: { $0.isEmpty },
                      emptyTitle: "No applications", emptyMessage: "Create Access applications in the Cloudflare dashboard; they appear here.", emptySymbol: "lock.shield",
                      retry: { Task { await zt.loadAll() } }) { list in
            List(list) { a in
                HStack {
                    VStack(alignment: .leading) {
                        Text(a.name)
                        Text([a.domain, a.sessionDuration.map { "Session \($0)" }, a.policies.map { "\($0.count) polic\($0.count == 1 ? "y" : "ies")" }].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete\u{2026}", role: .destructive) { zt.formError = nil; deleting = .app(a) }.disabled(!zt.canWrite(section))
                }
            }
        }
    }

    private var tokens: some View {
        LoadStateView(state: zt.tokens, permission: "Access: Service Tokens Read", isEmpty: { $0.isEmpty },
                      emptyTitle: "No service tokens", emptyMessage: "Create one for a script or service that needs to pass Access.", emptySymbol: "key",
                      retry: { Task { await zt.loadAll() } }) { list in
            List(list) { t in
                HStack {
                    VStack(alignment: .leading) {
                        Text(t.name)
                        Text([t.clientID, t.expiresAt.map { "Expires \($0.prefix(10))" }].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Delete\u{2026}", role: .destructive) { zt.formError = nil; deleting = .token(t) }.disabled(!zt.canWrite(section))
                }
            }
        }
    }
}


/// The one place a service token's secret is ever shown.
struct SecretSheet: View {
    let secret: NewServiceSecret
    var done: () -> Void
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy the secret for \(secret.name) now").font(.headline)
            Text("Cloudflare shows it once. Nephele doesn't keep it, and it can't be shown again.").foregroundStyle(.secondary)
            if let id = secret.clientID { LabeledContent("Client ID") { Text(id).monospaced().textSelection(.enabled) } }
            LabeledContent("Client secret") { Text(secret.secret).monospaced().textSelection(.enabled).lineLimit(2) }
            HStack {
                Button(copied ? "Copied" : "Copy secret", systemImage: "doc.on.doc") {
                    let pb = NSPasteboard.general
                    pb.prepareForNewContents(with: .currentHostOnly)
                    pb.setString(secret.secret, forType: .string)
                    pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                    copied = true
                }
                Spacer()
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480)
    }
}
