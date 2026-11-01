import AppIntents
import Foundation

/// The training widgets and their dashboard cards.
nonisolated enum TrainingKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case load, week, recovery, predictions, plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .load: String(localized: "Charge d'entraînement")
        case .week: String(localized: "Semaine d'entraînement")
        case .recovery: String(localized: "Récupération")
        case .predictions: String(localized: "Prédictions de course")
        case .plan: String(localized: "Prochaine séance")
        }
    }

    var shortTitle: String {
        switch self {
        case .load: String(localized: "Charge")
        case .week: String(localized: "Semaine")
        case .recovery: String(localized: "Récup.")
        case .predictions: String(localized: "Prédictions")
        case .plan: String(localized: "Séance")
        }
    }

    var symbol: String {
        switch self {
        case .load: "speedometer"
        case .week: "calendar"
        case .recovery: "hourglass"
        case .predictions: "flag.checkered"
        case .plan: "list.bullet.clipboard"
        }
    }

    var explanation: String {
        switch self {
        case .load:
            String(localized: "La charge aiguë additionne la charge de vos séances des 7 derniers jours. Garmin la compare à votre charge chronique (4 semaines) : dans la plage optimale, vous progressez sans vous blesser. L'équilibre de charge montre comment vos 4 dernières semaines se répartissent entre aérobie légère, aérobie intense et anaérobie, face aux cibles de votre niveau.")
        case .week:
            String(localized: "Le volume de la semaine, du lundi à aujourd'hui, comparé à la semaine précédente. La répartition par zones de fréquence cardiaque aide à suivre la règle du 80/20 : environ 80 % du temps en zones 1–2, 20 % au-dessus.")
        case .recovery:
            String(localized: "Le temps de récupération est calculé par Garmin après chaque séance, puis ajusté avec votre sommeil, votre stress et votre VFC. Une séance intense avant la fin de la récupération augmente la fatigue et le risque de blessure.")
        case .predictions:
            String(localized: "Garmin estime vos temps de course à partir de votre VO₂ max, de votre historique d'entraînement et de vos sorties récentes. Ils supposent un entraînement adapté à la distance.")
        case .plan:
            String(localized: "Les séances planifiées dans votre calendrier Garmin Connect et dans votre plan Garmin Coach, synchronisées avec votre montre.")
        }
    }
}

/// Distance shown by the small race-prediction widget (widget configuration).
nonisolated enum RaceDistance: String, CaseIterable, Codable, Sendable, Hashable {
    case fiveK, tenK, half, marathon

    var meters: Double {
        switch self {
        case .fiveK: 5000
        case .tenK: 10000
        case .half: 21097.5
        case .marathon: 42195
        }
    }

    var label: String {
        switch self {
        case .fiveK: "5 km"
        case .tenK: "10 km"
        case .half: String(localized: "Semi")
        case .marathon: String(localized: "Marathon")
        }
    }

    func seconds(in predictions: RacePredictions) -> Int? {
        switch self {
        case .fiveK: predictions.fiveK
        case .tenK: predictions.tenK
        case .half: predictions.halfMarathon
        case .marathon: predictions.marathon
        }
    }
}

extension RaceDistance: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Distance"

    static let caseDisplayRepresentations: [RaceDistance: DisplayRepresentation] = [
        .fiveK: "5 km",
        .tenK: "10 km",
        .half: "Semi-marathon",
        .marathon: "Marathon",
    ]
}

/// Where you stand in your recovery at a given moment (widgets render it per timeline entry).
nonisolated struct RecoveryState: Sendable, Hashable {
    var until: Date?
    var remaining: TimeInterval
    /// 0 right after the workout, 1 once recovered.
    var progress: Double
    var readinessScore: Int?
    var readinessLevel: String?

    var isRecovered: Bool { remaining <= 0 }

    static func make(_ snapshot: DashboardSnapshot, at now: Date = .now) -> RecoveryState? {
        guard let readiness = snapshot.trainingReadiness else { return nil }
        guard let until = readiness.recoveryUntil, until > now else {
            return RecoveryState(until: readiness.recoveryUntil, remaining: 0, progress: 1,
                                 readinessScore: readiness.score, readinessLevel: readiness.level)
        }
        let minutes = Double(readiness.recoveryTimeMinutes ?? 0)
        var start = readiness.measuredAt ?? until.addingTimeInterval(-minutes * 60)
        // Garmin starts the clock when the workout ends: use it when it's the trigger.
        if let activity = snapshot.lastActivity, let started = activity.startedAt {
            let end = started.addingTimeInterval(activity.durationSeconds ?? 0)
            if end <= start, until.timeIntervalSince(end) <= 4 * 24 * 3600 { start = end }
        }
        let total = max(until.timeIntervalSince(start), 60)
        return RecoveryState(
            until: until,
            remaining: until.timeIntervalSince(now),
            progress: min(max(now.timeIntervalSince(start) / total, 0), 1),
            readinessScore: readiness.score,
            readinessLevel: readiness.level
        )
    }

    /// "14 h", "45 min".
    var remainingText: String {
        let minutes = Int((remaining / 60).rounded(.up))
        return minutes >= 60 ? "\(Int((Double(minutes) / 60).rounded(.up))) h" : "\(max(minutes, 1)) min"
    }

    var advice: String {
        if !isRecovered {
            return remaining > 24 * 3600
                ? String(localized: "Repos ou séance très légère")
                : String(localized: "Séance facile conseillée")
        }
        switch readinessLevel {
        case "prime", "high": return String(localized: "Prêt pour une séance intense")
        case "moderate": return String(localized: "Séance modérée conseillée")
        case "low", "poor": return String(localized: "Privilégiez la récupération")
        default: return String(localized: "Récupération terminée")
        }
    }
}

nonisolated extension DashboardSnapshot {
    /// Today's workout if still to do, else the next one (rest days only if nothing else).
    var nextWorkout: PlannedWorkout? {
        let today = calendarDate
        let pending = upcomingWorkouts.filter { $0.date >= today && !$0.completed }
        return pending.first(where: { !$0.isRestDay }) ?? pending.first
    }

    /// Today's planned workout, done or not.
    var todaysWorkout: PlannedWorkout? {
        upcomingWorkouts.first { $0.date == calendarDate && !$0.isRestDay }
    }
}

nonisolated extension PlannedWorkout {
    /// "Aujourd'hui", "Demain", "Jeudi".
    var dayLabel: String {
        guard let day else { return date }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Aujourd'hui") }
        if calendar.isDateInTomorrow(day) { return String(localized: "Demain") }
        return day.formatted(.dateTime.weekday(.wide)).capitalized(with: .current)
    }

    var title: String {
        if isRestDay { return String(localized: "Repos") }
        if let name, !name.isEmpty { return name }
        return sport.map(GarminTerms.activityName) ?? String(localized: "Séance")
    }

    var symbol: String {
        if isRestDay { return "bed.double.fill" }
        if isRace { return "flag.checkered" }
        return GarminTerms.activitySymbol(sport ?? "")
    }
}
