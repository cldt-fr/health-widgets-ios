import AppIntents
import SwiftUI
import WidgetKit

/// "My day at a glance": rings for the key metrics (medium) or a full board (large).
struct OverviewWidgetView: View {
    var entry: HealthEntry
    var family: WidgetFamily

    static let preferred: [MetricKind] = [.bodyBattery, .sleep, .readiness, .steps, .hrv, .stress, .heartRate, .intensityMinutes]

    var body: some View {
        if let snapshot = entry.snapshot {
            let readings = Self.preferred.compactMap { snapshot.reading($0) }
            if readings.isEmpty {
                WidgetEmptyView(kind: .readiness, family: family, message: entry.message)
            } else if family == .systemLarge || family == .systemExtraLarge {
                large(snapshot, readings)
            } else {
                medium(snapshot, readings)
            }
        } else {
            WidgetEmptyView(kind: .readiness, family: family, message: entry.message)
        }
    }

    private func medium(_ snapshot: DashboardSnapshot, _ readings: [MetricReading]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            OverviewHeader(snapshot: snapshot, showsRefresh: false)
            HStack(spacing: 10) {
                ForEach(readings.prefix(4), id: \.kind) { reading in
                    VStack(spacing: 6) {
                        RingValue(reading: reading, lineWidth: 7, valueSize: 17)
                        Text(reading.kind.shortTitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .widgetURL(DeepLink.metric(reading.kind))
                }
            }
        }
    }

    private func large(_ snapshot: DashboardSnapshot, _ readings: [MetricReading]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OverviewHeader(snapshot: snapshot, showsRefresh: true)
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: min(readings.count, 6), by: 2)), id: \.self) { index in
                    HStack(spacing: 10) {
                        OverviewTile(reading: readings[index])
                        if index + 1 < min(readings.count, 6) {
                            OverviewTile(reading: readings[index + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            if let battery = snapshot.reading(.bodyBattery), !battery.series.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        MetricTitle(kind: .bodyBattery, size: 10)
                        Spacer()
                        Text(battery.detail ?? "")
                            .font(.metric(10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    SparklineChart(points: battery.series, colors: MetricKind.bodyBattery.colors, domain: 0...100)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct OverviewHeader: View {
    var snapshot: DashboardSnapshot
    var showsRefresh: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalDay.date(from: snapshot.calendarDate) ?? .now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.metric(14))
                    .lineLimit(1)
                if snapshot.needsReauth {
                    Label("Reconnexion requise", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                } else if let sync = snapshot.source.lastSyncAt {
                    Text("Synchro \(sync, format: .dateTime.hour().minute())")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let device = snapshot.source.deviceName, !showsRefresh {
                Text(device)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsRefresh {
                Button(intent: RefreshSnapshotIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .padding(7)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Actualiser"))
            }
        }
    }
}

struct OverviewTile: View {
    var reading: MetricReading

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RingGauge(progress: reading.progress ?? 0, colors: reading.kind.colors, lineWidth: 6)
                Image(systemName: reading.kind.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(reading.kind.gradient)
                    .widgetAccentable()
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 0) {
                Text(reading.kind.shortTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                ValueLabel(value: reading.value, unit: reading.unit, size: 22)
                if let label = reading.label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(reading.kind.gradient)
                        .widgetAccentable()
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
        .widgetURL(DeepLink.metric(reading.kind))
    }
}
