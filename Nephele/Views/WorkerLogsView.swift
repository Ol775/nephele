import SwiftUI
import CloudflareKit

struct WorkerLogsView: View {
    @State private var tail: TailStore
    init(script: String, session: Session) { _tail = State(initialValue: TailStore(session: session, script: script)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                statusLabel
                Spacer()
                Toggle("Errors only", isOn: $tail.errorsOnly)
                Button("Clear") { tail.clear() }.disabled(tail.events.isEmpty)
                if tail.state == .live || tail.state == .connecting {
                    Button("Stop") { Task { await tail.stop() } }
                } else {
                    Button("Start") { tail.start() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(10)
            if tail.samplingNotice {
                Label("This Worker is busy, so some log lines are being skipped. Turn on Errors only to see fewer.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            Divider()
            if tail.visibleEvents.isEmpty {
                ContentUnavailableView(tail.state == .live ? "Waiting for requests" : "Live logs are off", systemImage: "text.alignleft",
                                       description: Text(tail.state == .live ? "Requests to this Worker appear here as they happen." : "Press Start to watch requests as they happen."))
            } else {
                ScrollViewReader { proxy in
                    List(tail.visibleEvents) { event in
                        EventRow(event: event).id(event.id)
                    }
                    .onChange(of: tail.visibleEvents.count) { if let last = tail.visibleEvents.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .onDisappear { Task { await tail.stop() } }
    }

    @ViewBuilder private var statusLabel: some View {
        switch tail.state {
        case .idle: Label("Off", systemImage: "circle").foregroundStyle(.secondary)
        case .connecting: Label("Connecting", systemImage: "circle.dotted").foregroundStyle(.secondary)
        case .live: HStack(spacing: 6) { StatusDot(kind: .ok); Text("Live") }
        case .stopped(let reason): HStack(spacing: 6) { StatusDot(kind: reason == nil ? .muted : .bad); Text(reason ?? "Stopped").lineLimit(2) }
        }
    }
}

private struct EventRow: View {
    let event: TailEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                StatusDot(kind: event.isError ? .bad : .ok)
                Text(event.time.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                Text("\(event.method ?? "") \(event.url ?? "")").lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(event.outcome).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(event.logs.enumerated()), id: \.offset) { _, line in
                Text(line.text).monospaced().font(.footnote).foregroundStyle(line.level == "error" ? Color.red : .secondary)
            }
            ForEach(event.exceptions, id: \.self) { Text($0).monospaced().font(.footnote).foregroundStyle(.red) }
        }
        .padding(.vertical, 2)
    }
}
