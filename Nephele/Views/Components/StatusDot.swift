import SwiftUI

struct StatusDot: View {
    enum Kind { case ok, warning, bad, muted
        var color: Color { switch self { case .ok: .green; case .warning: .orange; case .bad: .red; case .muted: .secondary } }
    }
    let kind: Kind
    var body: some View {
        Circle().fill(kind.color).frame(width: 7, height: 7).accessibilityHidden(true)
    }
}
