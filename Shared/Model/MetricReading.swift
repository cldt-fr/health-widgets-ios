import Foundation

/// One metric, ready to display: the same shape feeds dashboard cards, detail screens
/// and every widget family, whatever the underlying payload looks like.
nonisolated struct MetricReading: Sendable, Hashable {
    struct Stat: Sendable, Hashable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    var kind: MetricKind
    var value: String
    var unit: String?
    /// Ring fill, 0...1. `nil` when the metric has no natural goal (HRV, heart rate...).
    var progress: Double?
    /// Qualitative state ("Équilibré", "Objectif 8 470"...).
    var label: String?
    /// One secondary line ("6,79 km", "Min 44 · Max 148"...).
    var detail: String?
    var series: [Point] = []
    var seriesDomain: ClosedRange<Double>?
    var history: [DailyValue] = []
    var historyGoal: Double?
    var stats: [Stat] = []

    static func placeholder(_ kind: MetricKind) -> MetricReading {
        MetricReading(kind: kind, value: "–", label: String(localized: "Pas de données"))
    }
}

nonisolated extension DashboardSnapshot {
    func reading(_ kind: MetricKind) -> MetricReading? {
        switch kind {
        case .bodyBattery: bodyBatteryReading
        case .sleep: sleepReading
        case .readiness: readinessReading
        case .hrv: hrvReading
        case .steps: stepsReading
        case .stress: stressReading
        case .heartRate: heartRateReading
        case .intensityMinutes: intensityReading
        case .calories: caloriesReading
        case .vo2Max: vo2MaxReading
        }
    }

    /// Metrics that actually have data today, in dashboard order.
    var availableMetrics: [MetricKind] {
        MetricKind.allCases.filter { reading($0) != nil }
    }

    private var bodyBatteryReading: MetricReading? {
        guard let bb = bodyBattery, let current = bb.current ?? bb.series.last.map({ Int($0.v) }) else { return nil }
        let level: String = switch current {
        case 75...: String(localized: "Pleine forme")
        case 50..<75: String(localized: "Bon niveau")
        case 25..<50: String(localized: "Moyen")
        default: String(localized: "Faible")
        }
        var stats: [MetricReading.Stat] = []
        if let charged = bb.charged { stats.append(.init(label: String(localized: "Rechargé"), value: "+\(charged)")) }
        if let drained = bb.drained { stats.append(.init(label: String(localized: "Dépensé"), value: "−\(drained)")) }
        if let high = bb.highest { stats.append(.init(label: String(localized: "Max"), value: "\(high)")) }
        if let low = bb.lowest { stats.append(.init(label: String(localized: "Min"), value: "\(low)")) }
        if let wake = bb.atWake { stats.append(.init(label: String(localized: "Au réveil"), value: "\(wake)")) }
        let detail: String? = switch (bb.charged, bb.drained) {
        case let (charged?, drained?): "+\(charged) / −\(drained)"
        default: nil
        }
        return MetricReading(
            kind: .bodyBattery,
            value: "\(current)",
            progress: Double(current) / 100,
            label: level,
            detail: detail,
            series: bb.series,
            seriesDomain: 0...100,
            stats: stats
        )
    }

    private var sleepReading: MetricReading? {
        guard let sleep, let duration = sleep.durationSeconds, duration > 0 else { return nil }
        var stats: [MetricReading.Stat] = [.init(label: String(localized: "Durée"), value: Fmt.duration(seconds: duration))]
        let stages: [(String, Int?)] = [
            (String(localized: "Profond"), sleep.deepSeconds),
            (String(localized: "Léger"), sleep.lightSeconds),
            (String(localized: "Paradoxal"), sleep.remSeconds),
            (String(localized: "Éveillé"), sleep.awakeSeconds),
        ]
        for (label, seconds) in stages where seconds != nil {
            stats.append(.init(label: label, value: Fmt.duration(seconds: seconds)))
        }
        if let hrv = sleep.avgOvernightHrv { stats.append(.init(label: String(localized: "VFC nuit"), value: "\(Fmt.integer(hrv)) ms")) }
        if let rhr = sleep.restingHeartRate { stats.append(.init(label: String(localized: "FC repos"), value: "\(rhr) bpm")) }
        let scoreText = sleep.score.map(String.init) ?? Fmt.duration(seconds: duration)
        return MetricReading(
            kind: .sleep,
            value: scoreText,
            progress: sleep.score.map { Double($0) / 100 },
            label: GarminTerms.label(sleep.quality),
            detail: Fmt.duration(seconds: duration),
            history: sleep.history,
            stats: stats
        )
    }

    private var readinessReading: MetricReading? {
        guard let readiness = trainingReadiness, let score = readiness.score else { return nil }
        var stats = readiness.factors.compactMap { factor -> MetricReading.Stat? in
            guard let label = GarminTerms.label(factor.key) else { return nil }
            let value = factor.percent.map { "\($0) %" } ?? GarminTerms.label(factor.feedback) ?? "–"
            return .init(label: label, value: value)
        }
        if let minutes = readiness.recoveryTimeMinutes {
            stats.insert(.init(label: String(localized: "Récupération"), value: minutes > 0 ? Fmt.duration(seconds: minutes * 60) : String(localized: "Terminée")), at: 0)
        }
        return MetricReading(
            kind: .readiness,
            value: "\(score)",
            progress: Double(score) / 100,
            label: GarminTerms.label(readiness.level),
            detail: GarminTerms.label(readiness.feedbackShort ?? readiness.feedbackLong),
            stats: stats
        )
    }

    private var hrvReading: MetricReading? {
        guard let hrv, let value = hrv.lastNightAvg ?? hrv.weeklyAvg else { return nil }
        var stats: [MetricReading.Stat] = []
        if let weekly = hrv.weeklyAvg { stats.append(.init(label: String(localized: "Moy. 7 jours"), value: "\(weekly) ms")) }
        if let high = hrv.lastNightHigh { stats.append(.init(label: String(localized: "Pic 5 min"), value: "\(high) ms")) }
        if let low = hrv.baseline?.balancedLow, let high = hrv.baseline?.balancedUpper {
            stats.append(.init(label: String(localized: "Plage habituelle"), value: "\(low)–\(high) ms"))
        }
        var progress: Double?
        if let low = hrv.baseline?.lowUpper, let high = hrv.baseline?.balancedUpper, high > low {
            // Position within an extended baseline band, so the ring "reads" like Garmin's gauge.
            let floor = Double(low) * 0.75, ceiling = Double(high) * 1.15
            progress = min(1, max(0.04, (Double(value) - floor) / (ceiling - floor)))
        }
        return MetricReading(
            kind: .hrv,
            value: "\(value)",
            unit: "ms",
            progress: progress,
            label: GarminTerms.label(hrv.status),
            detail: hrv.weeklyAvg.map { String(localized: "Moy. 7 j \($0) ms") },
            series: hrv.readings,
            history: hrv.history,
            stats: stats
        )
    }

    private var stepsReading: MetricReading? {
        guard let steps else { return nil }
        var stats: [MetricReading.Stat] = []
        if let distance = steps.distanceMeters { stats.append(.init(label: String(localized: "Distance"), value: Fmt.distance(meters: distance, imperial: usesImperialUnits))) }
        if let goal = steps.goal { stats.append(.init(label: String(localized: "Objectif"), value: Fmt.integer(goal))) }
        if let floors = floors?.ascended { stats.append(.init(label: String(localized: "Étages"), value: Fmt.integer(floors))) }
        return MetricReading(
            kind: .steps,
            value: Fmt.integer(steps.count),
            unit: String(localized: "pas"),
            progress: steps.goal.flatMap { $0 > 0 ? Double(steps.count) / Double($0) : nil },
            label: steps.goal.map { String(localized: "Objectif \(Fmt.integer($0))") },
            detail: steps.distanceMeters.map { Fmt.distance(meters: $0, imperial: usesImperialUnits) },
            history: steps.history,
            historyGoal: steps.goal.map(Double.init),
            stats: stats
        )
    }

    private var stressReading: MetricReading? {
        guard let stress, let value = stress.current ?? stress.average else { return nil }
        let level: String = switch value {
        case ..<26: String(localized: "Repos")
        case 26..<51: String(localized: "Faible")
        case 51..<76: String(localized: "Moyen")
        default: String(localized: "Élevé")
        }
        var stats: [MetricReading.Stat] = []
        if let average = stress.average { stats.append(.init(label: String(localized: "Moyenne"), value: "\(average)")) }
        if let max = stress.max { stats.append(.init(label: String(localized: "Max"), value: "\(max)")) }
        if let rest = stress.restSeconds { stats.append(.init(label: String(localized: "Repos"), value: Fmt.duration(seconds: rest))) }
        if let high = stress.highSeconds { stats.append(.init(label: String(localized: "Stress élevé"), value: Fmt.duration(seconds: high))) }
        return MetricReading(
            kind: .stress,
            value: "\(value)",
            progress: Double(value) / 100,
            label: GarminTerms.label(stress.qualifier) ?? level,
            detail: stress.average.map { String(localized: "Moyenne \($0)") },
            series: stress.series,
            seriesDomain: 0...100,
            stats: stats
        )
    }

    private var heartRateReading: MetricReading? {
        guard let hr = heartRate, let resting = hr.resting ?? hr.latest else { return nil }
        var stats: [MetricReading.Stat] = []
        if let avg = hr.restingSevenDayAvg { stats.append(.init(label: String(localized: "Moy. 7 jours"), value: "\(avg) bpm")) }
        if let min = hr.min { stats.append(.init(label: String(localized: "Min"), value: "\(min) bpm")) }
        if let max = hr.max { stats.append(.init(label: String(localized: "Max"), value: "\(max) bpm")) }
        if let latest = hr.latest { stats.append(.init(label: String(localized: "Dernière"), value: "\(latest) bpm")) }
        let values = hr.series.map(\.v)
        let domain: ClosedRange<Double>? = values.min().flatMap { low in
            values.max().map { high in max(30, low - 8)...(high + 8) }
        }
        let detail: String? = switch (hr.min, hr.max) {
        case let (min?, max?): String(localized: "Min \(min) · Max \(max)")
        default: nil
        }
        return MetricReading(
            kind: .heartRate,
            value: "\(resting)",
            unit: "bpm",
            label: hr.restingSevenDayAvg.map { String(localized: "Moy. 7 j \($0)") },
            detail: detail,
            series: hr.series,
            seriesDomain: domain,
            history: hr.history,
            stats: stats
        )
    }

    private var intensityReading: MetricReading? {
        guard let im = intensityMinutes, let total = im.weekTotal ?? im.today else { return nil }
        var stats: [MetricReading.Stat] = []
        if let moderate = im.moderate { stats.append(.init(label: String(localized: "Modérées"), value: "\(moderate) min")) }
        if let vigorous = im.vigorous { stats.append(.init(label: String(localized: "Intenses (×2)"), value: "\(vigorous) min")) }
        if let goal = im.weeklyGoal { stats.append(.init(label: String(localized: "Objectif semaine"), value: "\(goal) min")) }
        if let today = im.today { stats.append(.init(label: String(localized: "Aujourd'hui"), value: "+\(today) min")) }
        return MetricReading(
            kind: .intensityMinutes,
            value: "\(total)",
            unit: "min",
            progress: im.weeklyGoal.flatMap { $0 > 0 ? Double(total) / Double($0) : nil },
            label: im.weeklyGoal.map { String(localized: "Objectif \($0)") },
            detail: im.today.map { String(localized: "Aujourd'hui +\($0)") },
            stats: stats
        )
    }

    private var caloriesReading: MetricReading? {
        guard let calories, let active = calories.active ?? calories.total else { return nil }
        var stats: [MetricReading.Stat] = []
        if let value = calories.active { stats.append(.init(label: String(localized: "Actives"), value: "\(Fmt.integer(value)) kcal")) }
        if let value = calories.resting { stats.append(.init(label: String(localized: "Au repos"), value: "\(Fmt.integer(value)) kcal")) }
        if let value = calories.total { stats.append(.init(label: String(localized: "Totales"), value: "\(Fmt.integer(value)) kcal")) }
        // Only a real goal makes a ring meaningful (active/total is not one).
        let progress = calories.goal.flatMap { $0 > 0 ? Double(active) / Double($0) : nil }
        return MetricReading(
            kind: .calories,
            value: Fmt.integer(active),
            unit: "kcal",
            progress: progress,
            label: String(localized: "Actives"),
            detail: calories.total.map { String(localized: "Total \(Fmt.integer($0))") },
            stats: stats
        )
    }

    private var vo2MaxReading: MetricReading? {
        guard let status = trainingStatus, let vo2 = status.vo2Max ?? status.vo2MaxCycling else { return nil }
        var stats: [MetricReading.Stat] = []
        if let label = GarminTerms.label(status.status) { stats.append(.init(label: String(localized: "Statut"), value: label)) }
        if let acute = status.acuteLoad { stats.append(.init(label: String(localized: "Charge aiguë"), value: Fmt.integer(acute))) }
        if let chronic = status.chronicLoad { stats.append(.init(label: String(localized: "Charge chronique"), value: Fmt.integer(chronic))) }
        if let predictions = racePredictions {
            if let t = predictions.fiveK { stats.append(.init(label: "5 km", value: Fmt.clock(seconds: Double(t)))) }
            if let t = predictions.tenK { stats.append(.init(label: "10 km", value: Fmt.clock(seconds: Double(t)))) }
            if let t = predictions.halfMarathon { stats.append(.init(label: String(localized: "Semi"), value: Fmt.clock(seconds: Double(t)))) }
            if let t = predictions.marathon { stats.append(.init(label: String(localized: "Marathon"), value: Fmt.clock(seconds: Double(t)))) }
        }
        return MetricReading(
            kind: .vo2Max,
            value: Fmt.integer(vo2),
            unit: "ml/kg/min",
            // Scaled on a 30–70 range: from sedentary to elite endurance athlete.
            progress: min(1, max(0.05, (vo2 - 30) / 40)),
            label: GarminTerms.label(status.status),
            detail: status.acuteLoad.map { String(localized: "Charge \(Fmt.integer($0))") },
            stats: stats
        )
    }
}
