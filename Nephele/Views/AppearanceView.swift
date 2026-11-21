import SwiftUI
import AppKit

struct AppearanceView: View {
    @Environment(SettingsStore.self) private var store
    @State private var importText = ""
    @State private var importError: String?
    @State private var confirmReset = false

    static let presets: [(name: String, hex: String)] = [
        ("Cloudflare", "#F6821F"), ("Amber", "#FBAD41"), ("Ocean", "#2F7DE1"), ("Violet", "#7A5AF8"),
        ("Forest", "#2E9E5B"), ("Rose", "#E0457B"), ("Graphite", "#6F6A64"),
    ]

    var body: some View {
        let s = store.settings
        Form {
            Section("Look") {
                Picker("Appearance", selection: store.binding(\.theme)) {
                    Text("System").tag(ThemeChoice.system); Text("Light").tag(ThemeChoice.light); Text("Dark").tag(ThemeChoice.dark)
                }.pickerStyle(.segmented)
                LabeledContent("Accent colour") {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.hex) { preset in
                            Button { store.update { $0.accentHex = preset.hex } } label: {
                                Circle().fill(Color(hex: preset.hex)).frame(width: 22, height: 22)
                                    .overlay { if s.accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(NepheleTheme.readableInk(onHex: preset.hex)) } }
                            }
                            .buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name)
                        }
                        ColorPicker("Custom", selection: Binding(get: { Color(hex: s.accentHex) }, set: { c in store.update { $0.accentHex = c.hexString } }), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                Toggle("Tint the sidebar", isOn: store.binding(\.tintSidebar))
                LabeledContent("Corner radius") { Slider(value: store.binding(\.radius), in: 0...20, step: 1) { Text("Corner radius") }.frame(width: 220); Text("\(Int(s.radius)) px").monospacedDigit().frame(width: 50) }
                Picker("Icon weight", selection: store.binding(\.iconWeight)) { Text("Light").tag(1.4); Text("Regular").tag(1.8); Text("Bold").tag(2.3) }.pickerStyle(.segmented)
                Picker("Typeface", selection: store.binding(\.fontDesign)) {
                    Text("System").tag(FontChoice.system); Text("Rounded").tag(FontChoice.rounded); Text("Serif").tag(FontChoice.serif); Text("Mono").tag(FontChoice.mono)
                }.pickerStyle(.segmented)
                LabeledContent("Text size") { Slider(value: store.binding(\.fontSize), in: 12...18, step: 1) { Text("Text size") }.frame(width: 220); Text("\(Int(s.fontSize)) pt").monospacedDigit().frame(width: 50) }
            }
            Section("Layout") {
                Picker("Density", selection: store.binding(\.density)) { Text("Compact").tag(Density.compact); Text("Comfortable").tag(Density.comfortable) }.pickerStyle(.segmented)
                Picker("Sidebar", selection: store.binding(\.sidebarIcons)) { Text("Icons and labels").tag(false); Text("Icons only").tag(true) }.pickerStyle(.segmented)
                Picker("Open on", selection: store.binding(\.landing)) {
                    ForEach(s.nav.filter(\.visible)) { Text($0.id.title).tag($0.id) }
                }
                LabeledContent("Sidebar items") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(s.nav.enumerated()), id: \.element.id) { index, entry in
                            HStack {
                                Toggle(isOn: Binding(get: { entry.visible }, set: { on in store.update { $0.nav[index].visible = on } })) {
                                    Label(entry.id.title, systemImage: entry.id.symbol)
                                }
                                .disabled(entry.id == .appearance || entry.id == .settings)
                                Spacer()
                                Button("Move up", systemImage: "arrow.up") { move(index, by: -1) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                                Button("Move down", systemImage: "arrow.down") { move(index, by: 1) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                        }
                    }
                }
                LabeledContent("Overview sections") {
                    VStack(alignment: .leading) {
                        Toggle("Key numbers", isOn: store.binding(\.overview.stats))
                        Toggle("Requests chart", isOn: store.binding(\.overview.chart))
                        Toggle("Needs attention", isOn: store.binding(\.overview.alerts))
                        Toggle("Domains", isOn: store.binding(\.overview.domains))
                    }
                }
            }
            Section("Accessibility") {
                Toggle("Increase contrast", isOn: store.binding(\.highContrast))
                Toggle("Reduce motion", isOn: store.binding(\.reduceMotion))
            }
            Section("Backup") {
                Text("Copy these settings to keep your look, or paste saved ones below and apply them.").foregroundStyle(.secondary)
                TextEditor(text: .constant(store.exportJSON())).font(.system(.footnote, design: .monospaced)).frame(height: 110)
                HStack {
                    Button("Copy settings") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.exportJSON(), forType: .string) }
                }
                TextEditor(text: $importText).font(.system(.footnote, design: .monospaced)).frame(height: 90)
                HStack {
                    Button("Apply pasted settings") {
                        do { try store.importJSON(importText); importError = nil } catch { importError = (error as? LocalizedError)?.errorDescription }
                    }
                    Button("Reset to Cloudflare defaults", role: .destructive) { confirmReset = true }
                    if let importError { Text(importError).foregroundStyle(.red) }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all appearance and layout settings?", isPresented: $confirmReset) {
            Button("Reset settings", role: .destructive) { store.reset() }
        } message: { Text("Your look returns to the Cloudflare defaults. Your API token and account are not affected.") }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard store.settings.nav.indices.contains(target) else { return }
        store.update { $0.nav.swapAt(index, target) }
    }
}
