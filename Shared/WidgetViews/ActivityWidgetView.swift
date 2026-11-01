import SwiftUI
import WidgetKit

/// Last workout: the "did I train today?" widget.
struct ActivityWidgetView: View {
    var entry: HealthEntry
    var family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot, let activity = snapshot.lastActivity {
            if family == .systemMedium {
                medium(activity, imperial: snapshot.usesImperialUnits)
            } else {
                small(activity, imperial: snapshot.usesImperialUnits)
            }
        } else {
            WidgetEmptyView(kind: .intensityMinutes, family: family, message: entry.message ?? String(localized: "Aucune activité récente"))
        }
    }

    private func small(_ activity: Activity, imperial: Bool) -> some View {
        let style = ActivityStyle(activity.type)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                ActivityBadge(activity: activity, size: 34)
                Spacer()
                if let started = activity.startedAt {
                    Text(started, format: .relative(presentation: .named))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(activity.name ?? GarminTerms.activityName(activity.type))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Self.headline(activity, imperial: imperial))
                .font(.metric(28))
                .foregroundStyle(style.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            HStack(spacing: 8) {
                Label(Fmt.duration(seconds: activity.durationSeconds), systemImage: "timer")
                if let hr = activity.averageHr {
                    Label("\(hr)", systemImage: "heart.fill")
                }
            }
            .font(.metric(11, weight: .semibold))
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func medium(_ activity: Activity, imperial: Bool) -> some View {
        let style = ActivityStyle(activity.type)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ActivityBadge(activity: activity, size: 38)
                Spacer(minLength: 0)
                Text(activity.name ?? GarminTerms.activityName(activity.type))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let started = activity.startedAt {
                    Text(started, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(Self.headline(activity, imperial: imperial))
                    .font(.metric(32))
                    .foregroundStyle(style.gradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                StatGrid(stats: Self.stats(activity, imperial: imperial))
                if let aerobic = activity.aerobicEffect {
                    TrainingEffectBar(aerobic: aerobic, anaerobic: activity.anaerobicEffect ?? 0, label: GarminTerms.label(activity.effectLabel))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func headline(_ activity: Activity, imperial: Bool) -> String {
        if let distance = activity.distanceMeters, distance > 50 {
            return Fmt.distance(meters: distance, imperial: imperial)
        }
        return Fmt.duration(seconds: activity.durationSeconds)
    }

    static func stats(_ activity: Activity, imperial: Bool) -> [MetricReading.Stat] {
        var stats: [MetricReading.Stat] = [
            .init(label: String(localized: "Durée"), value: Fmt.clock(seconds: activity.movingSeconds ?? activity.durationSeconds)),
        ]
        let type = activity.type.lowercased()
        if activity.distanceMeters ?? 0 > 50, let speed = activity.averageSpeed {
            if type.contains("run") || type.contains("walk") || type.contains("hik") {
                stats.append(.init(label: String(localized: "Allure"), value: Fmt.pace(metersPerSecond: speed, imperial: imperial)))
            } else {
                stats.append(.init(label: String(localized: "Vitesse"), value: Fmt.speed(metersPerSecond: speed, imperial: imperial)))
            }
        }
        if let hr = activity.averageHr { stats.append(.init(label: String(localized: "FC moy."), value: "\(hr) bpm")) }
        if let calories = activity.calories { stats.append(.init(label: String(localized: "Calories"), value: "\(Fmt.integer(calories))")) }
        if let gain = activity.elevationGain, gain > 5, stats.count < 4 {
            stats.append(.init(label: String(localized: "D+"), value: "\(Fmt.integer(gain)) m"))
        }
        return Array(stats.prefix(4))
    }
}

struct ActivityStyle {
    var colors: [Color]

    init(_ type: String) {
        let type = type.lowercased()
        colors = if type.contains("run") {
            MetricKind.calories.colors
        } else if type.contains("cycl") || type.contains("bik") {
            MetricKind.vo2Max.colors
        } else if type.contains("swim") {
            MetricKind.hrv.colors
        } else if type.contains("strength") || type.contains("yoga") {
            MetricKind.sleep.colors
        } else {
            MetricKind.readiness.colors
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct ActivityBadge: View {
    var activity: Activity
    var size: CGFloat

    var body: some View {
        let style = ActivityStyle(activity.type)
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: GarminTerms.activitySymbol(activity.type))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: style.colors[0].opacity(0.45), radius: size * 0.25, y: size * 0.1)
            .widgetAccentable()
    }
}

/// Garmin's aerobic / anaerobic training effect (0–5) as two segmented bars.
struct TrainingEffectBar: View {
    var aerobic: Double
    var anaerobic: Double
    var label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(String(localized: "Aérobie"), aerobic, MetricKind.bodyBattery.colors)
            row(String(localized: "Anaérobie"), anaerobic, MetricKind.sleep.colors)
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ value: Double, _ colors: [Color]) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 58, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Double(index) < value.rounded(.down) ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary.opacity(0.12)))
                        .frame(height: 4)
                }
            }
            .widgetAccentable()
            Text(Fmt.decimal(value)).frame(width: 22, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
