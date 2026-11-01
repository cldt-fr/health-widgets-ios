import Foundation
import WidgetKit

/// What every widget renders from (also used by the in-app widget gallery).
nonisolated struct HealthEntry: TimelineEntry, Sendable {
    var date: Date
    var snapshot: DashboardSnapshot?
    var metric: MetricKind = .bodyBattery
    /// Shown when there is nothing to display yet (not connected, first sync...).
    var message: String?

    static func preview(_ metric: MetricKind = .bodyBattery) -> HealthEntry {
        HealthEntry(date: .now, snapshot: DemoData.snapshot(), metric: metric)
    }
}

nonisolated enum DeepLink {
    static let scheme = "healthwidgets"

    static func metric(_ kind: MetricKind) -> URL {
        URL(string: "\(scheme)://metric/\(kind.rawValue)")!
    }

    static let activity = URL(string: "\(scheme)://activity")!
    static let dashboard = URL(string: "\(scheme)://dashboard")!
}
