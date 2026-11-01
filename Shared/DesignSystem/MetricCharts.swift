import Charts
import SwiftUI
import WidgetKit

/// Smooth intraday curve with a fading gradient fill and a glowing "now" dot.
struct SparklineChart: View {
    var points: [Point]
    var colors: [Color]
    var domain: ClosedRange<Double>?
    var lineWidth: CGFloat = 2.2
    var showsArea = true
    var showsLastPoint = true

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var resolvedDomain: ClosedRange<Double> {
        if let domain { return domain }
        let values = points.map(\.v)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        let domain = resolvedDomain
        let fullColor = renderingMode == .fullColor
        Chart {
            ForEach(points, id: \.t) { point in
                if showsArea {
                    AreaMark(
                        x: .value("Heure", point.date),
                        yStart: .value("Base", domain.lowerBound),
                        yEnd: .value("Valeur", point.v)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colors[0].opacity(fullColor ? 0.38 : 0.25), colors[0].opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                LineMark(x: .value("Heure", point.date), y: .value("Valeur", point.v))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(
                        fullColor
                            ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.primary)
                    )
            }
            if showsLastPoint, let last = points.last {
                PointMark(x: .value("Heure", last.date), y: .value("Valeur", last.v))
                    .symbolSize(lineWidth * 18)
                    .foregroundStyle(fullColor ? colors[1] : .primary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Last seven days as rounded bars, today highlighted, optional dashed goal line.
struct HistoryBars: View {
    var values: [DailyValue]
    var colors: [Color]
    var goal: Double?
    var showsLabels = true

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let today = values.last?.date
        let fullColor = renderingMode == .fullColor
        Chart {
            ForEach(values.suffix(7), id: \.date) { day in
                BarMark(
                    x: .value("Jour", day.date),
                    y: .value("Valeur", day.value ?? 0),
                    width: .ratio(0.62)
                )
                .cornerRadius(4, style: .continuous)
                .foregroundStyle(
                    day.date == today
                        ? (fullColor ? AnyShapeStyle(LinearGradient(colors: colors.reversed(), startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.primary))
                        : AnyShapeStyle((fullColor ? colors[0] : Color.primary).opacity(0.32))
                )
            }
            if let goal, goal > 0 {
                RuleMark(y: .value("Objectif", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            if showsLabels {
                AxisMarks { value in
                    AxisValueLabel {
                        if let day = value.as(String.self) {
                            Text(Fmt.weekday(day)).font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Night timeline: deep at the bottom, awake on top, like Garmin's sleep chart.
struct HypnogramChart: View {
    var stages: [SleepSegment]
    var showsAxis = false

    private static let order: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        Chart(stages, id: \.start) { segment in
            RectangleMark(
                xStart: .value("Début", segment.startDate),
                xEnd: .value("Fin", segment.endDate),
                y: .value("Phase", Palette.name(for: segment.stage)),
                height: .ratio(0.86)
            )
            .cornerRadius(2.5, style: .continuous)
            .foregroundStyle(Palette.color(for: segment.stage))
        }
        .chartYScale(domain: Self.order.map(Palette.name(for:)))
        .chartYAxis(.hidden)  // stage colours + legend read better than band labels
        .chartXAxis {
            if showsAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
        }
        .chartLegend(.hidden)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Proportional capsule of the night's stages.
struct SleepStagesBar: View {
    var sleep: SleepMetric
    var height: CGFloat = 8

    var body: some View {
        let parts: [(SleepStage, Double)] = [SleepStage.deep, .light, .rem, .awake].compactMap { stage in
            sleep.seconds(in: stage).map { (stage, Double($0)) }
        }
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { stage, seconds in
                    Capsule()
                        .fill(Palette.color(for: stage))
                        .frame(width: max(height, (proxy.size.width - CGFloat(parts.count - 1) * 2) * seconds / total))
                }
            }
        }
        .frame(height: height)
        .widgetAccentable()
    }
}
