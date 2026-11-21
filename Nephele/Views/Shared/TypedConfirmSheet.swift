import SwiftUI

/// "Type the name to confirm" for deleting a namespace, database, bucket or Worker.
struct TypedConfirmSheet: View {
    let title: String
    let message: String
    let name: String
    let buttonLabel: String
    let error: String?
    var onConfirm: (String) async -> Void
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary)
            TextField(name, text: $typed).textFieldStyle(.roundedBorder).accessibilityLabel("Type the name to confirm")
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(buttonLabel, role: .destructive) {
                    working = true
                    Task { await onConfirm(typed); working = false; onDone() }
                }
                .disabled(typed != name || working)
            }
        }
        .padding(20).frame(width: 440)
    }
}
