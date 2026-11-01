import AppIntents
import SwiftUI
import WidgetKit

struct MetricConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Métrique" }
    static var description: IntentDescription { "Choisissez la métrique à afficher." }

    @Parameter(title: "Métrique", default: .bodyBattery)
    var metric: MetricKind

    init() {}

    init(metric: MetricKind) {
        self.metric = metric
    }
}

struct MetricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        SnapshotTimeline.placeholder(metric: .bodyBattery)
    }

    func snapshot(for configuration: MetricConfigurationIntent, in context: Context) async -> HealthEntry {
        await SnapshotTimeline.entry(metric: configuration.metric, isPreview: context.isPreview).0
    }

    func timeline(for configuration: MetricConfigurationIntent, in context: Context) async -> Timeline<HealthEntry> {
        await SnapshotTimeline.timeline(metric: configuration.metric, context: context)
    }
}

struct MetricWidgetEntryView: View {
    var entry: HealthEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        MetricWidgetView(entry: entry, family: family)
    }
}

struct MetricWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MetricWidget", intent: MetricConfigurationIntent.self, provider: MetricProvider()) { entry in
            MetricWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(kind: entry.metric) }
                .widgetURL(DeepLink.metric(entry.metric))
        }
        .configurationDisplayName("Métrique")
        .description("Body Battery, sommeil, VFC, pas… la métrique de votre choix.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OverviewWidget", provider: StaticSnapshotProvider()) { entry in
            OverviewEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(kind: .readiness) }
                .widgetURL(DeepLink.dashboard)
        }
        .configurationDisplayName("Ma journée")
        .description("Énergie, sommeil, forme et pas en un coup d'œil.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct OverviewEntryView: View {
    var entry: HealthEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        OverviewWidgetView(entry: entry, family: family)
    }
}

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ActivityWidget", provider: StaticSnapshotProvider(metric: .intensityMinutes)) { entry in
            ActivityEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(kind: .calories) }
                .widgetURL(DeepLink.activity)
        }
        .configurationDisplayName("Dernière activité")
        .description("Votre dernière séance : distance, durée, allure et effet d'entraînement.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ActivityEntryView: View {
    var entry: HealthEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ActivityWidgetView(entry: entry, family: family)
    }
}

#Preview("Body Battery", as: .systemSmall) {
    MetricWidget()
} timeline: {
    HealthEntry.preview(.bodyBattery)
}

#Preview("Sommeil", as: .systemMedium) {
    MetricWidget()
} timeline: {
    HealthEntry.preview(.sleep)
}

#Preview("Ma journée", as: .systemLarge) {
    OverviewWidget()
} timeline: {
    HealthEntry.preview()
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    MetricWidget()
} timeline: {
    HealthEntry.preview(.readiness)
}
