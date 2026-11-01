import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Providers

/// Recovery counts down by itself: one entry every 20 minutes until the next refresh,
/// so the ring keeps moving even when WidgetKit delays the network refresh.
struct RecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        SnapshotTimeline.placeholder(metric: .readiness)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HealthEntry) -> Void) {
        let isPreview = context.isPreview
        Task {
            completion(await SnapshotTimeline.entry(metric: .readiness, isPreview: isPreview).0)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HealthEntry>) -> Void) {
        let isPreview = context.isPreview
        Task {
            let (entry, interval) = await SnapshotTimeline.entry(metric: .readiness, isPreview: isPreview)
            let entries = stride(from: 0.0, through: 8 * 3600, by: 20 * 60).map { offset in
                var next = entry
                next.date = entry.date.addingTimeInterval(offset)
                return next
            }
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(interval))))
        }
    }
}

struct RaceDistanceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Distance" }
    static var description: IntentDescription { "Choisissez la distance à afficher." }

    @Parameter(title: "Distance", default: .tenK)
    var distance: RaceDistance
}

struct RacePredictionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        SnapshotTimeline.placeholder(metric: .vo2Max)
    }

    func snapshot(for configuration: RaceDistanceIntent, in context: Context) async -> HealthEntry {
        var entry = await SnapshotTimeline.entry(metric: .vo2Max, isPreview: context.isPreview).0
        entry.raceDistance = configuration.distance
        return entry
    }

    func timeline(for configuration: RaceDistanceIntent, in context: Context) async -> Timeline<HealthEntry> {
        let (entry, interval) = await SnapshotTimeline.entry(metric: .vo2Max, isPreview: context.isPreview)
        var configured = entry
        configured.raceDistance = configuration.distance
        return Timeline(entries: [configured], policy: .after(.now.addingTimeInterval(interval)))
    }
}

// MARK: - Widgets

struct TrainingEntryView: View {
    var kind: TrainingKind
    var entry: HealthEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TrainingWidgetView(kind: kind, entry: entry, family: family)
    }
}

private extension WidgetConfiguration {
    func trainingConfiguration(_ kind: TrainingKind, description: LocalizedStringKey) -> some WidgetConfiguration {
        configurationDisplayName(kind.title)
            .description(Text(description))
    }
}

struct TrainingLoadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrainingLoadWidget", provider: StaticSnapshotProvider(metric: .vo2Max)) { entry in
            TrainingEntryView(kind: .load, entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(training: .load) }
                .widgetURL(DeepLink.training(.load))
        }
        .trainingConfiguration(.load, description: "Charge aiguë, plage optimale et équilibre aérobie/anaérobie.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TrainingWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrainingWeekWidget", provider: StaticSnapshotProvider(metric: .intensityMinutes)) { entry in
            TrainingEntryView(kind: .week, entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(training: .week) }
                .widgetURL(DeepLink.training(.week))
        }
        .trainingConfiguration(.week, description: "Volume de la semaine par sport et zones de fréquence cardiaque.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryWidget", provider: RecoveryProvider()) { entry in
            TrainingEntryView(kind: .recovery, entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(training: .recovery) }
                .widgetURL(DeepLink.training(.recovery))
        }
        .trainingConfiguration(.recovery, description: "Compte à rebours de récupération et conseil pour la séance du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RacePredictionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RacePredictionsWidget", intent: RaceDistanceIntent.self, provider: RacePredictionsProvider()) { entry in
            TrainingEntryView(kind: .predictions, entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(training: .predictions) }
                .widgetURL(DeepLink.training(.predictions))
        }
        .trainingConfiguration(.predictions, description: "Vos temps estimés du 5 km au marathon, avec l'allure.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkoutWidget", provider: StaticSnapshotProvider(metric: .readiness)) { entry in
            TrainingEntryView(kind: .plan, entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(training: .plan) }
                .widgetURL(DeepLink.training(.plan))
        }
        .trainingConfiguration(.plan, description: "Votre séance du jour et les suivantes (calendrier Garmin et Garmin Coach).")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

#Preview("Charge", as: .systemMedium) {
    TrainingLoadWidget()
} timeline: {
    HealthEntry.preview()
}

#Preview("Semaine", as: .systemMedium) {
    TrainingWeekWidget()
} timeline: {
    HealthEntry.preview()
}

#Preview("Récupération", as: .systemSmall) {
    RecoveryWidget()
} timeline: {
    HealthEntry.preview()
}
