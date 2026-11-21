import SwiftUI

struct NepheleTheme: Sendable {
    let accent: Color
    let accentInk: Color
    let radius: CGFloat
    let pad: CGFloat
    let rowPad: CGFloat
    let fontDesign: Font.Design
    let iconWeight: Font.Weight
    let fontSize: CGFloat
    let tintSidebar: Bool

    init(_ s: AppSettings) {
        accent = Color(hex: s.accentHex)
        accentInk = Self.readableInk(onHex: s.accentHex)
        radius = s.radius
        pad = s.density == .compact ? 14 : 20
        rowPad = s.density == .compact ? 6 : 11
        fontDesign = switch s.fontDesign { case .system: .default; case .rounded: .rounded; case .serif: .serif; case .mono: .monospaced }
        iconWeight = s.iconWeight < 1.6 ? .light : (s.iconWeight < 2.0 ? .regular : .semibold)
        fontSize = s.fontSize
        tintSidebar = s.tintSidebar
    }

    /// Relative luminance above 0.3 reads better with dark text on top.
    static func prefersDarkInk(onHex hex: String) -> Bool {
        let (r, g, b) = Color.rgb(hex: hex)
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) > 0.3
    }

    static func readableInk(onHex hex: String) -> Color {
        prefersDarkInk(onHex: hex) ? Color(hex: "#1A1100") : .white
    }
}

extension Color {
    static func rgb(hex: String) -> (Double, Double, Double) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let n = UInt32(digits, radix: 16) else { return (0.96, 0.51, 0.12) }
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }
    init(hex: String) {
        let (r, g, b) = Color.rgb(hex: hex)
        self.init(.sRGB, red: r, green: g, blue: b)
    }
}

extension EnvironmentValues {
    @Entry var nepheleTheme = NepheleTheme(AppSettings())
}
