import SwiftUI
import AppKit

/// A plain-text code editor. SwiftUI's TextEditor follows the system smart quote and dash settings, which would
/// turn `"` into curly quotes and corrupt JavaScript, so this wraps an NSTextView with every substitution off.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat

    static func configure(_ tv: NSTextView) {
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.allowsUndo = true
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let tv = scroll.documentView as? NSTextView {
            Self.configure(tv)
            tv.delegate = context.coordinator
            tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            tv.string = text
            tv.drawsBackground = false
        }
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
