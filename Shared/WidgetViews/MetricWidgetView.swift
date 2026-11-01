import SwiftUI
import WidgetKit

/// One metric, every family: Home Screen (small, medium) and Lock Screen (circular,
/// rectangular, inline).
struct MetricWidgetView: View {
    var entry: HealthEntry
    var family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot, let reading = snapshot.reading(entry.metric) {
            switch family {
            case .systemMedium, .systemLarge, .systemExtraLarge:
                MediumMetricView(reading: reading, snapshot: snapshot)
            case .accessoryCircular:
                CircularMetricView(reading: reading)
            case .accessoryRectangular:
                RectangularMetricView(reading: reading)
            case .accessoryInline:
                InlineMetricView(reading: reading)
            default:
                SmallMetricView(reading: reading, snapshot: snapshot)
            }
        } else {
            WidgetEmptyView(kind: entry.metric, family: family, message: entry.message)
        }
    }
}

// MARK: - Home Screen

struct SmallMetricView: View {
    var reading: MetricReading
    var snapshot: DashboardSnapshot

    private var kind: MetricKind { reading.kind }

    private var prefersChart: Bool {
        switch kind {
        case .bodyBattery, .stress, .heartRate, .hrv:
            !reading.series.isEmpty || !reading.history.isEmpty
        default:
            false
        }
    }

    var body: some View {
        if prefersChart {
            chartLayout
        } else if reading.progress == nil {
            statLayout
        } else {
            ringLayout
        }
    }

    private var statLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetricTitle(kind: kind, compact: true)
            ValueLabel(value: reading.value, unit: reading.unit, size: 38)
                .padding(.top, 6)
            if let label = reading.label {
                Text(label)
                    .font(.metric(12, weight: .semibold))
                    .foregroundStyle(kind.gradient)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            Spacer(minLength: 6)
            StatGrid(stats: Array(reading.stats.filter { $0.label != reading.label }.prefix(2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ringLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricTitle(kind: kind, compact: true)
            RingValue(reading: reading, lineWidth: 12, valueSize: 30, showsIcon: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            WidgetFooter(reading: reading, snapshot: snapshot)
        }
    }

    private var chartLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                MetricTitle(kind: kind, compact: true)
                Spacer(minLength: 4)
                if let progress = reading.progress {
                    RingGauge(progress: progress, colors: kind.colors, lineWidth: 4.5)
                        .frame(width: 24, height: 24)
                }
            }
            ValueLabel(value: reading.value, unit: reading.unit, size: 40)
                .padding(.top, 6)
            if let label = snapshot.needsReauth ? String(localized: "Reconnexion requise") : reading.label {
                Text(label)
                    .font(.metric(12, weight: .semibold))
                    .foregroundStyle(kind.gradient)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            Spacer(minLength: 6)
            Group {
                if !reading.series.isEmpty {
                    SparklineChart(points: reading.series, colors: kind.colors, domain: reading.seriesDomain)
                } else {
                    HistoryBars(values: reading.history, colors: kind.colors, goal: reading.historyGoal, showsLabels: false)
                }
            }
            .frame(height: 38)
        }
    }
}

struct WidgetFooter: View {
    var reading: MetricReading
    var snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 4) {
            if snapshot.needsReauth {
                Label("Reconnexion", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.metric(11, weight: .semibold))
                    .foregroundStyle(.orange)
            } else if let label = reading.label {
                Text(label)
                    .font(.metric(12, weight: .semibold))
                    .foregroundStyle(reading.kind.gradient)
                    .widgetAccentable()
            }
            Spacer(minLength: 2)
            if let detail = reading.detail, reading.label == nil || detail.count < 9 {
                Text(detail)
                    .font(.metric(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct MediumMetricView: View {
    var reading: MetricReading
    var snapshot: DashboardSnapshot

    private var kind: MetricKind { reading.kind }

    var body: some View {
        HStack(spacing: 16) {
            leading
                .frame(width: 116)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                MetricTitle(kind: kind)
                if let label = reading.label {
                    Text(label)
                        .font(.metric(18))
                        .foregroundStyle(kind.gradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                }
                if snapshot.needsReauth {
                    Label("Reconnexion requise", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.metric(11, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if let detail = reading.detail {
                    Text(detail)
                        .font(.metric(12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailingVisual
            }
        }
    }

    @ViewBuilder private var leading: some View {
        if reading.progress != nil {
            RingValue(reading: reading, lineWidth: 13, valueSize: 32)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MetricBadge(kind: kind, size: 34)
                ValueLabel(value: reading.value, unit: reading.unit, size: 40)
                if let first = reading.stats.first {
                    Text("\(first.label) \(first.value)")
                        .font(.metric(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trailingVisual: some View {
        switch kind {
        case .sleep:
            if let sleep = snapshot.sleep, !sleep.stages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HypnogramChart(stages: sleep.stages).frame(height: 44)
                    HStack {
                        Text(Fmt.time(sleep.start))
                        Spacer()
                        Text(Fmt.time(sleep.end))
                    }
                    .font(.metric(10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            } else {
                StatGrid(stats: Array(reading.stats.prefix(4)))
            }
        case .readiness:
            FactorBars(factors: snapshot.trainingReadiness?.factors ?? [], colors: kind.colors, limit: 3)
        case .vo2Max, .intensityMinutes, .calories:
            StatGrid(stats: Array(reading.stats.dropFirst(kind == .vo2Max ? 3 : 0).prefix(4)))
        default:
            if !reading.series.isEmpty {
                SparklineChart(points: reading.series, colors: kind.colors, domain: reading.seriesDomain)
                    .frame(height: 56)
            } else if !reading.history.isEmpty {
                HistoryBars(values: reading.history, colors: kind.colors, goal: reading.historyGoal)
                    .frame(height: 62)
            } else {
                StatGrid(stats: Array(reading.stats.prefix(4)))
            }
        }
    }
}

/// Two columns of label/value pairs.
struct StatGrid: View {
    var stats: [MetricReading.Stat]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                GridRow {
                    cell(stats[index])
                    if index + 1 < stats.count { cell(stats[index + 1]) }
                }
            }
        }
    }

    private func cell(_ stat: MetricReading.Stat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stat.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(stat.value)
                .font(.metric(14, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Training readiness contributors as thin progress bars.
struct FactorBars: View {
    var factors: [ReadinessFactor]
    var colors: [Color]
    var limit: Int = 6

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(factors.prefix(limit), id: \.key) { factor in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(GarminTerms.label(factor.key) ?? factor.key)
                        Spacer()
                        Text(GarminTerms.label(factor.feedback) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1))
                            Capsule()
                                .fill(renderingMode == .fullColor ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary))
                                .frame(width: proxy.size.width * CGFloat(min(max(Double(factor.percent ?? 0) / 100, 0.03), 1)))
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

// MARK: - Lock Screen

struct CircularMetricView: View {
    var reading: MetricReading

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let progress = reading.progress {
                RingGauge(progress: progress, colors: reading.kind.colors, lineWidth: 5)
                    .padding(2.5)
            }
            VStack(spacing: -2) {
                Image(systemName: reading.kind.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .widgetAccentable()
                Text(reading.value)
                    .font(.metric(reading.value.count > 3 ? 14 : 19))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(reading.kind.title) \(reading.value) \(reading.unit ?? "")"))
    }
}

struct RectangularMetricView: View {
    var reading: MetricReading

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: reading.kind.symbol)
                    .widgetAccentable()
                Text(reading.kind.title)
                    .textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ValueLabel(value: reading.value, unit: reading.unit, size: 24)
                if let label = reading.label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if let progress = reading.progress {
                Gauge(value: min(max(progress, 0), 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
            } else if !reading.series.isEmpty {
                SparklineChart(points: reading.series, colors: reading.kind.colors, domain: reading.seriesDomain, lineWidth: 1.6, showsArea: false)
                    .frame(height: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineMetricView: View {
    var reading: MetricReading

    var body: some View {
        Label {
            Text("\(reading.value)\(reading.unit.map { " \($0)" } ?? "") · \(reading.kind.shortTitle)")
        } icon: {
            Image(systemName: reading.kind.symbol)
        }
    }
}

// MARK: - Empty state

struct WidgetEmptyView: View {
    var kind: MetricKind
    var family: WidgetFamily
    var message: String?

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: kind.symbol).font(.title3)
            }
        case .accessoryInline:
            Label(kind.shortTitle, systemImage: kind.symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(kind.title, systemImage: kind.symbol).font(.headline)
                Text(message ?? String(localized: "Pas de données")).font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                MetricTitle(kind: kind, compact: family == .systemSmall)
                Spacer(minLength: 0)
                MetricBadge(kind: kind, size: 30)
                Text(message ?? String(localized: "Pas encore de données aujourd'hui"))
                    .font(.metric(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
