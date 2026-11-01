import Foundation

// Mirrors `backend/src/healthwidgets/schemas.py` (camelCase JSON, UTC ISO-8601 dates,
// time series in epoch seconds). Every metric is optional: devices don't all measure
// everything, and a section can fail to load while the others still display.

nonisolated struct DashboardSnapshot: Codable, Sendable, Hashable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var calendarDate: String
    var generatedAt: Date
    var stale: Bool = false
    var needsReauth: Bool = false
    var source: Source
    var unitSystem: String?

    var steps: StepsMetric?
    var calories: CaloriesMetric?
    var floors: FloorsMetric?
    var heartRate: HeartRateMetric?
    var bodyBattery: BodyBatteryMetric?
    var stress: StressMetric?
    var sleep: SleepMetric?
    var hrv: HrvMetric?
    var trainingReadiness: TrainingReadinessMetric?
    var trainingStatus: TrainingStatusMetric?
    var intensityMinutes: IntensityMinutesMetric?
    var spo2: Spo2Metric?
    var respiration: RespirationMetric?
    var lastActivity: Activity?
    var recentActivities: [Activity] = []
    var racePredictions: RacePredictions?

    var warnings: [String] = []

    var usesImperialUnits: Bool { unitSystem == "statute" }
}

nonisolated struct Point: Codable, Sendable, Hashable {
    var t: Int
    var v: Double

    var date: Date { Date(timeIntervalSince1970: TimeInterval(t)) }
}

nonisolated struct DailyValue: Codable, Sendable, Hashable {
    var date: String
    var value: Double?
    var goal: Double?

    var day: Date? { LocalDay.date(from: date) }
}

nonisolated struct Source: Codable, Sendable, Hashable {
    var provider: String
    var deviceName: String?
    var deviceImageUrl: String?
    var lastSyncAt: Date?
}

nonisolated struct StepsMetric: Codable, Sendable, Hashable {
    var count: Int
    var goal: Int?
    var distanceMeters: Double?
    var history: [DailyValue] = []
}

nonisolated struct CaloriesMetric: Codable, Sendable, Hashable {
    var total: Int?
    var active: Int?
    var resting: Int?
    var goal: Int?
}

nonisolated struct FloorsMetric: Codable, Sendable, Hashable {
    var ascended: Double?
    var goal: Double?
}

nonisolated struct HeartRateMetric: Codable, Sendable, Hashable {
    var resting: Int?
    var min: Int?
    var max: Int?
    var restingSevenDayAvg: Int?
    var latest: Int?
    var series: [Point] = []
    var history: [DailyValue] = []
}

nonisolated struct BodyBatteryMetric: Codable, Sendable, Hashable {
    var current: Int?
    var highest: Int?
    var lowest: Int?
    var charged: Int?
    var drained: Int?
    var atWake: Int?
    var series: [Point] = []
}

nonisolated struct StressMetric: Codable, Sendable, Hashable {
    var average: Int?
    var max: Int?
    var current: Int?
    var qualifier: String?
    var restSeconds: Int?
    var lowSeconds: Int?
    var mediumSeconds: Int?
    var highSeconds: Int?
    var series: [Point] = []
}

nonisolated enum SleepStage: String, Codable, Sendable, Hashable, CaseIterable {
    case deep, light, rem, awake

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SleepStage(rawValue: raw) ?? .light
    }
}

nonisolated struct SleepSegment: Codable, Sendable, Hashable {
    var start: Int
    var end: Int
    var stage: SleepStage

    var duration: TimeInterval { TimeInterval(end - start) }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(start)) }
    var endDate: Date { Date(timeIntervalSince1970: TimeInterval(end)) }
}

nonisolated struct SleepMetric: Codable, Sendable, Hashable {
    var calendarDate: String
    var score: Int?
    var quality: String?
    var durationSeconds: Int?
    var deepSeconds: Int?
    var lightSeconds: Int?
    var remSeconds: Int?
    var awakeSeconds: Int?
    var napSeconds: Int?
    var start: Date?
    var end: Date?
    var needSeconds: Int?
    var avgOvernightHrv: Double?
    var restingHeartRate: Int?
    var avgRespiration: Double?
    var avgSpo2: Double?
    var avgStress: Double?
    var bodyBatteryChange: Int?
    var feedback: String?
    var stages: [SleepSegment] = []
    var history: [DailyValue] = []

    func seconds(in stage: SleepStage) -> Int? {
        switch stage {
        case .deep: deepSeconds
        case .light: lightSeconds
        case .rem: remSeconds
        case .awake: awakeSeconds
        }
    }
}

nonisolated struct HrvBaseline: Codable, Sendable, Hashable {
    var lowUpper: Int?
    var balancedLow: Int?
    var balancedUpper: Int?
}

nonisolated struct HrvMetric: Codable, Sendable, Hashable {
    var lastNightAvg: Int?
    var lastNightHigh: Int?
    var weeklyAvg: Int?
    var status: String?
    var feedback: String?
    var baseline: HrvBaseline?
    var readings: [Point] = []
    var history: [DailyValue] = []
}

nonisolated struct ReadinessFactor: Codable, Sendable, Hashable {
    var key: String
    var percent: Int?
    var feedback: String?
    var value: Double?
}

nonisolated struct TrainingReadinessMetric: Codable, Sendable, Hashable {
    var score: Int?
    var level: String?
    var feedbackShort: String?
    var feedbackLong: String?
    var recoveryTimeMinutes: Int?
    var measuredAt: Date?
    var factors: [ReadinessFactor] = []
}

nonisolated struct TrainingStatusMetric: Codable, Sendable, Hashable {
    var status: String?
    var feedbackPhrase: String?
    var vo2Max: Double?
    var vo2MaxCycling: Double?
    var acuteLoad: Double?
    var chronicLoad: Double?
    var loadRatio: Double?
    var acwrStatus: String?
}

nonisolated struct IntensityMinutesMetric: Codable, Sendable, Hashable {
    var moderate: Int?
    var vigorous: Int?
    var weekTotal: Int?
    var weeklyGoal: Int?
    var today: Int?
}

nonisolated struct Spo2Metric: Codable, Sendable, Hashable {
    var average: Int?
    var lowest: Int?
    var latest: Int?
}

nonisolated struct RespirationMetric: Codable, Sendable, Hashable {
    var wakingAvg: Double?
    var sleepAvg: Double?
    var lowest: Double?
    var highest: Double?
}

nonisolated struct Activity: Codable, Sendable, Hashable, Identifiable {
    var id: Int
    var name: String?
    var type: String
    var startedAt: Date?
    var durationSeconds: Double?
    var movingSeconds: Double?
    var distanceMeters: Double?
    var calories: Double?
    var averageHr: Int?
    var maxHr: Int?
    var averageSpeed: Double?
    var elevationGain: Double?
    var aerobicEffect: Double?
    var anaerobicEffect: Double?
    var effectLabel: String?
    var trainingLoad: Double?
    var vo2Max: Double?
}

nonisolated struct RacePredictions: Codable, Sendable, Hashable {
    var fiveK: Int?
    var tenK: Int?
    var halfMarathon: Int?
    var marathon: Int?
}
