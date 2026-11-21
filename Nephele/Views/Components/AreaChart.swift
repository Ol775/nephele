import SwiftUI
import Charts
import CloudflareKit

struct AreaChart: View {
    let points: [TrafficPoint]
    @Environment(\.nepheleTheme) private var theme

    var body: some View {
        Chart(points, id: \.date) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Requests", point.requests))
                .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.28), theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", point.date), y: .value("Requests", point.requests))
                .foregroundStyle(theme.accent).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour()) } }
        .frame(height: 170)
        .accessibilityLabel("Requests over time")
    }
}

extension Int {
    var compact: String { formatted(.number.notation(.compactName)) }
}
