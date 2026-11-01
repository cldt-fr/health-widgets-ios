import Foundation
import WidgetKit

/// Timeline logic shared by every widget: fetch fresh data with a short timeout, fall
/// back to the App Group cache, and come back sooner after a failure.
enum SnapshotTimeline {
    /// Garmin data only moves when the watch syncs (every ~15 min): 30 min keeps widgets
    /// fresh while staying well within WidgetKit's daily refresh budget.
    static let refreshInterval: TimeInterval = 30 * 60
    static let retryInterval: TimeInterval = 15 * 60

    static func entry(metric: MetricKind, isPreview: Bool) async -> (HealthEntry, TimeInterval) {
        let repository = SnapshotRepository()
        // The widget gallery shows the demo day, so people see the widget before connecting.
        if isPreview {
            return (HealthEntry(date: .now, snapshot: repository.cached() ?? DemoData.snapshot(), metric: metric), refreshInterval)
        }
        guard repository.isConfigured else {
            // Credentials unreadable from the extension (or not onboarded yet): the app
            // still writes every snapshot to the App Group, so show the last one if any.
            if repository.settings.isOnboarded, let cached = repository.cache.load() {
                return (HealthEntry(date: .now, snapshot: cached, metric: metric), retryInterval)
            }
            let message = String(localized: "Ouvrez Health Widgets pour connecter votre montre")
            return (HealthEntry(date: .now, snapshot: nil, metric: metric, message: message), refreshInterval)
        }
        do {
            let result = try await repository.load(timeout: 15)
            let interval = result.error == nil ? refreshInterval : retryInterval
            return (HealthEntry(date: .now, snapshot: result.snapshot, metric: metric), interval)
        } catch {
            let message = (error as? APIError)?.errorDescription
            return (HealthEntry(date: .now, snapshot: repository.cached(), metric: metric, message: message), retryInterval)
        }
    }

    static func timeline(metric: MetricKind, context: TimelineProviderContext) async -> Timeline<HealthEntry> {
        let (entry, interval) = await self.entry(metric: metric, isPreview: context.isPreview)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(interval)))
    }

    static func placeholder(metric: MetricKind) -> HealthEntry {
        HealthEntry(date: .now, snapshot: DemoData.snapshot(), metric: metric)
    }
}

/// Timeline provider for widgets without configuration (overview, last activity).
struct StaticSnapshotProvider: TimelineProvider {
    var metric: MetricKind = .readiness

    func placeholder(in context: Context) -> HealthEntry {
        SnapshotTimeline.placeholder(metric: metric)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HealthEntry) -> Void) {
        let metric = metric
        let isPreview = context.isPreview
        Task {
            let (entry, _) = await SnapshotTimeline.entry(metric: metric, isPreview: isPreview)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HealthEntry>) -> Void) {
        let metric = metric
        let isPreview = context.isPreview
        Task {
            let (entry, interval) = await SnapshotTimeline.entry(metric: metric, isPreview: isPreview)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(interval))))
        }
    }
}
