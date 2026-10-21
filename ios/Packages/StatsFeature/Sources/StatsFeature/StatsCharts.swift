import Charts
import DesignSystem
import SwiftUI

/// Chart palette (doc 14 §1): wake = flame, battle = volt, training = cyan.
enum StatsPalette {
    static var wake: Color { Color(ColorTokens.brandFlame) }
    static var battle: Color { Color(ColorTokens.brandVolt) }
    static var training: Color { Color(ColorTokens.brandCyan) }
    static var lime: Color { Color(ColorTokens.brandLime) }
    static var axis: Color { Color(ColorTokens.textTertiary) }
    static var grid: Color { Color(ColorTokens.strokeSubtle) }

    static func tier(_ tier: Int) -> Color {
        switch tier {
        case 1: Color(ColorTokens.leagueBronze)
        case 2: Color(ColorTokens.leagueSilver)
        case 3: Color(ColorTokens.leagueGold)
        case 4: Color(ColorTokens.leaguePlatinum)
        default: Color(ColorTokens.leagueDiamond)
        }
    }
}

extension StatsSeries.Bucket {
    var unit: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

private func axisStyle() -> some AxisContent {
    AxisMarks { _ in
        AxisGridLine().foregroundStyle(StatsPalette.grid)
        AxisValueLabel().foregroundStyle(StatsPalette.axis)
    }
}

/// Chart 1 — daily push-ups stacked by context, scrub to see a bucket's numbers.
struct DailyBarsChart: View {
    let bars: [StatsSeries.Bar]
    let bucket: StatsSeries.Bucket
    @State private var selected: Date?

    private var wakeLabel: String { String(localized: "Wake") }
    private var battleLabel: String { String(localized: "Battle") }
    private var trainingLabel: String { String(localized: "Training") }

    private func bar(at date: Date?) -> StatsSeries.Bar? {
        guard let date else { return nil }
        return bars.last { (StatsSeries.date($0.start) ?? .distantFuture) <= date }
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                if let day = StatsSeries.date(bar.start) {
                    BarMark(x: .value("Date", day, unit: bucket.unit), y: .value("Push-ups", bar.wake))
                        .foregroundStyle(by: .value("Type", wakeLabel))
                    BarMark(x: .value("Date", day, unit: bucket.unit), y: .value("Push-ups", bar.battle))
                        .foregroundStyle(by: .value("Type", battleLabel))
                    BarMark(x: .value("Date", day, unit: bucket.unit), y: .value("Push-ups", bar.training))
                        .foregroundStyle(by: .value("Type", trainingLabel))
                }
            }
            if let pick = bar(at: selected), let day = StatsSeries.date(pick.start) {
                RuleMark(x: .value("Date", day, unit: bucket.unit))
                    .foregroundStyle(StatsPalette.axis.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: pick.start, lines: [
                            "\(pick.total) " + String(localized: "push-ups"),
                            "\(wakeLabel) \(pick.wake) · \(battleLabel) \(pick.battle) · \(trainingLabel) \(pick.training)",
                        ])
                    }
            }
        }
        .chartForegroundStyleScale(domain: [wakeLabel, battleLabel, trainingLabel],
                                   range: [StatsPalette.wake, StatsPalette.battle, StatsPalette.training])
        .chartXSelection(value: $selected)
        .chartYAxis { axisStyle() }
        .chartXAxis { axisStyle() }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }
}

/// Chart 2 — cumulative push-ups with milestone markers.
struct CumulativeChart: View {
    let points: [StatsSeries.Point]
    let milestones: [StatsSeries.Point]

    var body: some View {
        Chart {
            ForEach(points) { p in
                if let day = StatsSeries.date(p.date) {
                    AreaMark(x: .value("Date", day, unit: .day), y: .value("Total", p.value))
                        .foregroundStyle(LinearGradient(colors: [StatsPalette.wake.opacity(0.4), StatsPalette.wake.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", day, unit: .day), y: .value("Total", p.value))
                        .foregroundStyle(StatsPalette.wake)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(milestones) { m in
                if let day = StatsSeries.date(m.date) {
                    PointMark(x: .value("Date", day, unit: .day), y: .value("Total", m.value))
                        .foregroundStyle(StatsPalette.lime)
                        .symbolSize(80)
                        .annotation(position: .top) {
                            Text(verbatim: m.value >= 1000 ? "\(m.value / 1000)k" : "\(m.value)")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(StatsPalette.lime)
                        }
                }
            }
        }
        .chartYAxis { axisStyle() }
        .chartXAxis { axisStyle() }
        .frame(height: 200)
    }
}

/// Chart 3 — wake consistency: scheduled time (hollow ring) vs. completion (filled dot, green / red).
struct WakeTimesChart: View {
    let wakes: [StatsData.Wake]

    static func clock(_ minute: Double) -> String {
        let m = Int(minute.rounded()) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    private var domain: ClosedRange<Double> {
        let values = wakes.flatMap { [$0.scheduledMinute, $0.completedMinute].compactMap { $0 } }
        let low = (values.min() ?? 360) - 20
        let high = (values.max() ?? 480) + 20
        return low...max(high, low + 60)
    }

    var body: some View {
        Chart {
            ForEach(wakes, id: \.date) { w in
                if let day = StatsSeries.date(w.date) {
                    if let s = w.scheduledMinute {
                        RectangleMark(x: .value("Date", day, unit: .day), yStart: .value("Time", s - 10),
                                      yEnd: .value("Time", s + 10), width: .ratio(0.9))
                            .foregroundStyle(StatsPalette.grid.opacity(0.6))
                        PointMark(x: .value("Date", day, unit: .day), y: .value("Time", s))
                            .symbol {
                                Circle().strokeBorder(StatsPalette.axis, lineWidth: 2).frame(width: 10, height: 10)
                            }
                    }
                    if let c = w.completedMinute {
                        PointMark(x: .value("Date", day, unit: .day), y: .value("Time", c))
                            .foregroundStyle(w.status == "succeeded" ? Color(ColorTokens.stateSuccess) : Color(ColorTokens.stateDanger))
                            .symbolSize(70)
                    } else if let s = w.scheduledMinute {
                        PointMark(x: .value("Date", day, unit: .day), y: .value("Time", s))
                            .symbol(.cross)
                            .foregroundStyle(Color(ColorTokens.stateDanger))
                    }
                }
            }
        }
        // Earlier times on top: a reversed two-value domain.
        .chartYScale(domain: [domain.upperBound, domain.lowerBound])
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(StatsPalette.grid)
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(verbatim: Self.clock(m)) }
                }
                .foregroundStyle(StatsPalette.axis)
            }
        }
        .chartXAxis { axisStyle() }
        .frame(height: 200)
    }
}

/// Chart 4 — best set per active day; stars mark records within the period.
struct BestSetChart: View {
    let points: [StatsSeries.Point]

    var body: some View {
        Chart {
            ForEach(points) { p in
                if let day = StatsSeries.date(p.date) {
                    LineMark(x: .value("Date", day, unit: .day), y: .value("Best set", p.value))
                        .foregroundStyle(StatsPalette.battle)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    if p.isRecord {
                        PointMark(x: .value("Date", day, unit: .day), y: .value("Best set", p.value))
                            .symbol {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(ColorTokens.leagueGold))
                            }
                    } else {
                        PointMark(x: .value("Date", day, unit: .day), y: .value("Best set", p.value))
                            .foregroundStyle(StatsPalette.battle)
                            .symbolSize(30)
                    }
                }
            }
        }
        .chartYAxis { axisStyle() }
        .chartXAxis { axisStyle() }
        .frame(height: 180)
    }
}

/// Chart 6 — activity heatmap for the last 53 weeks (5-step lime scale, doc 14 §1).
struct HeatmapView: View {
    let cells: [StatsSeries.HeatCell]

    static func color(level: Int) -> Color {
        let steps: [Double] = [0.15, 0.35, 0.55, 0.78, 1.0]
        return StatsPalette.lime.opacity(steps[min(max(level, 0), 4)])
    }

    var body: some View {
        let weeks = (cells.map(\.week).max() ?? 0) + 1
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            Canvas { context, size in
                let gap: CGFloat = 2
                let side = min((size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (size.height - gap * 6) / 7)
                for cell in cells {
                    let rect = CGRect(x: CGFloat(cell.week) * (side + gap), y: CGFloat(cell.weekday) * (side + gap),
                                      width: side, height: side)
                    context.fill(Path(roundedRect: rect, cornerRadius: side / 4), with: .color(Self.color(level: cell.level)))
                }
            }
            .frame(height: 96)
            HStack(spacing: SpacingTokens.xs) {
                Text("Less").typography(TypographyTokens.caption)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(level: level)).frame(width: 10, height: 10)
                }
                Text("More").typography(TypographyTokens.caption)
            }
            .foregroundStyle(StatsPalette.axis)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Activity over the last year: push-ups on \(cells.filter { $0.reps > 0 }.count) days"))
    }
}

struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).typography(TypographyTokens.caption).foregroundStyle(StatsPalette.axis)
            ForEach(lines, id: \.self) { Text(verbatim: $0).typography(TypographyTokens.bodyS) }
        }
        .foregroundStyle(Color(ColorTokens.textPrimary))
        .padding(SpacingTokens.s)
        .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
    }
}
