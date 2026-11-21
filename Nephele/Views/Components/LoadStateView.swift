import SwiftUI
import CloudflareKit

struct EmptyStateView: View {
    let title: String
    let message: String
    var symbol = "tray"
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(message) }
            .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct PermissionPrompt: View {
    @Environment(Navigator.self) private var navigator
    let permission: String
    var body: some View {
        ContentUnavailableView {
            Label("Your token can't read this", systemImage: "lock")
        } description: {
            Text("Add the \(permission) permission to your API token, then refresh.")
        } actions: {
            Button("Open Settings") { navigator.openSettings() }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

/// One place for the loading, failed, permission and empty states every data region needs.
struct LoadStateView<T: Sendable, Content: View>: View {
    let state: LoadState<T>
    var permission: String?
    var isEmpty: (T) -> Bool = { _ in false }
    var emptyTitle = "Nothing here yet"
    var emptyMessage = ""
    var emptySymbol = "tray"
    var retry: (() -> Void)?
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let error):
            if case .permissionDenied = error, let permission {
                PermissionPrompt(permission: permission)
            } else {
                ContentUnavailableView {
                    Label("Couldn't load this", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.errorDescription ?? "Something went wrong.")
                } actions: {
                    if let retry { Button("Try again", action: retry) }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        case .loaded(let value):
            if isEmpty(value) { EmptyStateView(title: emptyTitle, message: emptyMessage, symbol: emptySymbol) } else { content(value) }
        }
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var caption: String?
    var emphasized = false
    @Environment(\.nepheleTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: emphasized ? 34 : 24, weight: .bold, design: theme.fontDesign)).monospacedDigit()
                .foregroundStyle(emphasized ? theme.accent : .primary)
            if let caption { Text(caption).font(.footnote).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.pad)
        .background(emphasized ? theme.accent.opacity(0.1) : Color.clear)
    }
}
