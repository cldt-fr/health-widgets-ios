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
            let result = try await WidgetSnapshotLoader.shared.load(repository)
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

/// One network fetch for all the widgets of this extension: reuses the snapshot the app
/// (or another widget) saved a moment ago, and merges simultaneous requests, instead of
/// every widget kind downloading the same snapshot after each reload.
actor WidgetSnapshotLoader {
    static let shared = WidgetSnapshotLoader()
    /// The app saves each snapshot it fetches, then reloads the widgets: reuse it.
    static let freshness: TimeInterval = 5 * 60

    private var inFlight: Task<SnapshotRepository.Result, Error>?

    func load(_ repository: SnapshotRepository) async throws -> SnapshotRepository.Result {
        if !repository.settings.isDemoMode, let age = repository.cache.age, age < Self.freshness,
           let cached = repository.cache.load() {
            return SnapshotRepository.Result(snapshot: cached, source: .cache)
        }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await repository.load(timeout: 15) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
