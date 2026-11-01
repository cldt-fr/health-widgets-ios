import Foundation

/// Realistic synthetic day, generated on device: offline demo mode, SwiftUI previews and
/// widget placeholders. Deterministic per calendar day (same seed → same curves).
nonisolated enum DemoData {
    /// DEBUG: `-demoHour 20.5` renders the demo day as if it were 20:30 (screenshots).
    static var clock: Date {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "demoHour"), let hour = Double(raw) {
            return Calendar.current.startOfDay(for: .now).addingTimeInterval(hour * 3600)
        }
        #endif
        return .now
    }

    static func snapshot(for now: Date = DemoData.clock, calendar: Calendar = .current) -> DashboardSnapshot {
        var rng = SeededGenerator(seed: UInt64(calendar.ordinality(of: .day, in: .era, for: now) ?? 1))
        let midnight = calendar.startOfDay(for: now)
        let hoursElapsed = now.timeIntervalSince(midnight) / 3600
        let day = LocalDay.string(from: now, calendar: calendar)
        func at(_ hour: Double) -> Date { midnight.addingTimeInterval(hour * 3600) }
        func epoch(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

        // Sleep: ~23:05 → ~07:10
        let bedtime = at(-1 + Double.random(in: -0.4...0.3, using: &rng))
        let wake = at(7 + Double.random(in: -0.3...0.4, using: &rng))
        var stages: [SleepSegment] = []
        var cursor = bedtime
        let cycle: [SleepStage] = [.light, .deep, .light, .rem]
        var index = 0
        while cursor < wake {
            var stage = cycle[index % cycle.count]
            if index > 2, Double.random(in: 0...1, using: &rng) < 0.12 { stage = .awake }
            let early = index < 6
            let minutes: Double = switch stage {
            case .light: .random(in: 18...38, using: &rng)
            case .deep: .random(in: 15...35, using: &rng) * (early ? 1.4 : 0.6)
            case .rem: .random(in: 10...25, using: &rng) * (early ? 0.7 : 1.5)
            case .awake: .random(in: 2...7, using: &rng)
            }
            let end = min(wake, cursor.addingTimeInterval(minutes * 60))
            stages.append(SleepSegment(start: epoch(cursor), end: epoch(end), stage: stage))
            cursor = end
            index += 1
        }
        func total(_ stage: SleepStage) -> Int { stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.end - $1.start } }
        let asleep = stages.filter { $0.stage != .awake }.reduce(0) { $0 + $1.end - $1.start }
        let sleepScore = min(96, max(55, 62 + (asleep - 6 * 3600) / 360 + Int.random(in: -4...8, using: &rng)))

        // Intraday series, 15-minute resolution up to now.
        let wakeHour = wake.timeIntervalSince(midnight) / 3600
        let workoutHour = 18.25
        var hr: [Point] = [], bb: [Point] = [], stress: [Point] = []
        var battery = 32.0
        var hour = 0.0
        while hour <= min(hoursElapsed, 24) {
            let t = epoch(at(hour))
            let sleeping = hour < wakeHour
            let workout = hour >= workoutHour && hour < workoutHour + 0.9
            let heart: Double
            if sleeping {
                heart = 49 + 4 * sin(hour) + .random(in: -2...2, using: &rng)
                battery = min(100, battery + .random(in: 1.4...2.1, using: &rng))
                stress.append(Point(t: t, v: .random(in: 6...18, using: &rng).rounded()))
            } else if workout {
                heart = 148 + .random(in: -8...12, using: &rng)
                battery = max(5, battery - .random(in: 2.5...4, using: &rng))
            } else {
                heart = 66 + 10 * sin((hour - 9) / 3) + .random(in: -5...9, using: &rng)
                battery = max(5, battery - .random(in: 0.6...1.4, using: &rng))
                let level = 32 + 18 * sin(hour / 2.3) + .random(in: -10...14, using: &rng)
                stress.append(Point(t: t, v: min(85, max(8, level)).rounded()))
            }
            hr.append(Point(t: t, v: heart.rounded()))
            bb.append(Point(t: t, v: battery.rounded()))
            hour += 0.25
        }
        let bbValues = bb.map(\.v)
        let awakeFraction = max(0, min(1, (hoursElapsed - wakeHour) / (22 - wakeHour)))
        let didWorkout = hoursElapsed > workoutHour + 0.9
        let steps = Int(Double.random(in: 9500...14500, using: &rng) * awakeFraction)
        let rhr = 47 + Int.random(in: -2...3, using: &rng)
        let hrv = 58 + Int.random(in: -7...6, using: &rng)

        func history(_ range: ClosedRange<Int>, today: Double, goal: Double? = nil) -> [DailyValue] {
            (1...6).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: midnight).map {
                    DailyValue(date: LocalDay.string(from: $0, calendar: calendar), value: Double(Int.random(in: range, using: &rng)), goal: goal)
                }
            } + [DailyValue(date: day, value: today, goal: goal)]
        }

        let run = Activity(
            id: 1, name: String(localized: "Course à pied"), type: "running",
            startedAt: at(workoutHour), durationSeconds: 3120, movingSeconds: 3080,
            distanceMeters: 10240, calories: 640, averageHr: 151, maxHr: 172,
            averageSpeed: 3.32, elevationGain: 96, aerobicEffect: 3.6, anaerobicEffect: 1.1,
            effectLabel: "TEMPO", trainingLoad: 152, vo2Max: 54
        )
        let ride = Activity(
            id: 2, name: String(localized: "Vélo"), type: "cycling",
            startedAt: at(-6.5), durationSeconds: 5400, movingSeconds: 5200,
            distanceMeters: 42800, calories: 980, averageHr: 138, maxHr: 166,
            averageSpeed: 8.2, elevationGain: 520, aerobicEffect: 3.1, anaerobicEffect: 0.8,
            effectLabel: "AEROBIC_BASE", trainingLoad: 142, vo2Max: nil
        )
        let activities = didWorkout ? [run, ride] : [ride]
        let readiness = 84 - (didWorkout ? 9 : 0) + Int.random(in: -5...5, using: &rng)
        // Recovery clock: restarts at the end of today's workout, else counts from waking up.
        let recoveryStart = didWorkout ? at(workoutHour + 0.9) : wake
        let recoveryMinutes = didWorkout ? 14 * 60 : 150

        return DashboardSnapshot(
            schemaVersion: DashboardSnapshot.supportedSchemaVersion,
            calendarDate: day,
            generatedAt: now,
            source: Source(provider: "demo", deviceName: "Forerunner 965", lastSyncAt: now.addingTimeInterval(-7 * 60)),
            unitSystem: "metric",
            steps: StepsMetric(count: steps, goal: 10000, distanceMeters: Double(steps) * 0.78, history: history(5200...15800, today: Double(steps), goal: 10000)),
            calories: CaloriesMetric(total: 1720 + steps / 22 + (didWorkout ? 640 : 0), active: steps / 22 + (didWorkout ? 640 : 0), resting: 1720),
            floors: FloorsMetric(ascended: (12 * awakeFraction).rounded(), goal: 10),
            heartRate: HeartRateMetric(
                resting: rhr, min: Int(hr.map(\.v).min() ?? 44), max: Int(hr.map(\.v).max() ?? 150),
                restingSevenDayAvg: rhr + 1, latest: hr.last.map { Int($0.v) },
                series: hr, history: history(45...51, today: Double(rhr))
            ),
            bodyBattery: BodyBatteryMetric(
                current: bbValues.last.map { Int($0) }, highest: bbValues.max().map { Int($0) },
                lowest: bbValues.min().map { Int($0) }, charged: Int((bbValues.max() ?? 0) - (bbValues.first ?? 0)),
                drained: Int((bbValues.max() ?? 0) - (bbValues.last ?? 0)), atWake: bbValues.max().map { Int($0) },
                series: bb
            ),
            stress: StressMetric(
                average: stress.isEmpty ? nil : Int(stress.map(\.v).reduce(0, +) / Double(stress.count)),
                max: stress.map(\.v).max().map { Int($0) }, current: stress.last.map { Int($0.v) },
                qualifier: "balanced", restSeconds: 30600, lowSeconds: 14200, mediumSeconds: 6100, highSeconds: 1900,
                series: stress
            ),
            sleep: SleepMetric(
                calendarDate: day, score: sleepScore,
                quality: sleepScore >= 90 ? "excellent" : sleepScore >= 80 ? "good" : sleepScore >= 60 ? "fair" : "poor",
                durationSeconds: asleep, deepSeconds: total(.deep), lightSeconds: total(.light),
                remSeconds: total(.rem), awakeSeconds: total(.awake), start: bedtime, end: wake,
                needSeconds: 8 * 3600, avgOvernightHrv: Double(hrv), restingHeartRate: rhr,
                avgRespiration: 14.2, avgSpo2: 95, avgStress: 14, bodyBatteryChange: 61,
                feedback: "positive_long_and_deep", stages: stages,
                history: history(58...92, today: Double(sleepScore))
            ),
            hrv: HrvMetric(
                lastNightAvg: hrv, lastNightHigh: hrv + 21, weeklyAvg: 56, status: "balanced",
                feedback: "HRV_BALANCED_6", baseline: HrvBaseline(lowUpper: 44, balancedLow: 49, balancedUpper: 65),
                history: history(48...64, today: Double(hrv))
            ),
            trainingReadiness: TrainingReadinessMetric(
                score: readiness, level: readiness >= 95 ? "prime" : readiness >= 75 ? "high" : readiness >= 50 ? "moderate" : "low",
                feedbackShort: "WELL_RECOVERED", feedbackLong: "READY_FOR_ACTION",
                recoveryTimeMinutes: recoveryMinutes, measuredAt: recoveryStart,
                recoveryUntil: recoveryStart.addingTimeInterval(TimeInterval(recoveryMinutes * 60)),
                factors: [
                    ReadinessFactor(key: "sleep", percent: 88, feedback: "good", value: Double(sleepScore)),
                    ReadinessFactor(key: "recovery_time", percent: 92, feedback: "good"),
                    ReadinessFactor(key: "hrv", percent: 80, feedback: "good", value: Double(hrv)),
                    ReadinessFactor(key: "acute_load", percent: 64, feedback: "moderate", value: 642),
                    ReadinessFactor(key: "sleep_history", percent: 76, feedback: "good"),
                    ReadinessFactor(key: "stress_history", percent: 82, feedback: "good"),
                ]
            ),
            trainingStatus: TrainingStatusMetric(
                status: "productive", feedbackPhrase: "PRODUCTIVE_6", vo2Max: 54, vo2MaxCycling: 56,
                acuteLoad: 642, chronicLoad: 581, loadRatio: 1.1, acwrStatus: "optimal",
                acwrPercent: 46, optimalLoadMin: 465, optimalLoadMax: 872,
                loadFocus: LoadFocus(
                    aerobicLow: LoadFocusPart(value: 612, targetMin: 430, targetMax: 780),
                    aerobicHigh: LoadFocusPart(value: 338, targetMin: 360, targetMax: 620),
                    anaerobic: LoadFocusPart(value: 126, targetMin: 90, targetMax: 240),
                    feedback: "AEROBIC_HIGH_SHORTAGE"
                )
            ),
            intensityMinutes: IntensityMinutesMetric(
                moderate: 96 + (didWorkout ? 25 : 0), vigorous: 38 + (didWorkout ? 30 : 0),
                weekTotal: 172 + (didWorkout ? 85 : 0), weeklyGoal: 150, today: didWorkout ? 55 : 8
            ),
            spo2: Spo2Metric(average: 96, lowest: 89, latest: 97),
            respiration: RespirationMetric(wakingAvg: 15.1, sleepAvg: 14.2, lowest: 11, highest: 22),
            lastActivity: activities.first,
            recentActivities: activities,
            racePredictions: RacePredictions(fiveK: 21 * 60 + 34, tenK: 44 * 60 + 52, halfMarathon: 99 * 60 + 5, marathon: 208 * 60 + 40),
            trainingWeek: week(for: now, calendar: calendar, didWorkoutToday: didWorkout),
            upcomingWorkouts: plan(from: now, calendar: calendar, didWorkoutToday: didWorkout)
        )
    }

    /// A typical half-marathon block. Weekday: 0 = Monday.
    private static let block: [(weekday: Int, sport: String, minutes: Double, km: Double, load: Double, name: String, intent: String?)] = [
        (1, "running", 52, 10.2, 118, String(localized: "Endurance fondamentale"), "AEROBIC_LOW_SHORTAGE_BASE"),
        (2, "strength_training", 45, 0, 38, String(localized: "Renforcement"), nil),
        (3, "running", 48, 9.1, 162, String(localized: "Fractionné 6 × 800 m"), "ANAEROBIC_SPEED"),
        (5, "cycling", 105, 48, 151, String(localized: "Vélo endurance"), "AEROBIC_LOW_SHORTAGE_BASE"),
        (6, "running", 95, 18, 214, String(localized: "Sortie longue"), "LONG_WORKOUT"),
    ]

    private static func mondayIndex(_ date: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7  // Sunday = 1 in Calendar
    }

    private static func week(for now: Date, calendar: Calendar, didWorkoutToday: Bool) -> TrainingWeek {
        let today = calendar.startOfDay(for: now)
        let todayIndex = mondayIndex(today, calendar)
        let monday = calendar.date(byAdding: .day, value: -todayIndex, to: today) ?? today
        var days: [TrainingDay] = []
        var sports: [String: SportTotal] = [:]
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            var day = TrainingDay(date: LocalDay.string(from: date, calendar: calendar), count: 0, durationSeconds: 0, distanceMeters: 0, trainingLoad: 0)
            let done = offset < todayIndex || (offset == todayIndex && didWorkoutToday)
            for workout in block where workout.weekday == offset && done {
                day.count += 1
                day.durationSeconds += workout.minutes * 60
                day.distanceMeters += workout.km * 1000
                day.trainingLoad += workout.load
                day.sports.append(workout.sport)
                var total = sports[workout.sport] ?? SportTotal(type: workout.sport, count: 0, durationSeconds: 0, distanceMeters: 0)
                total.count += 1
                total.durationSeconds += workout.minutes * 60
                total.distanceMeters += workout.km * 1000
                sports[workout.sport] = total
            }
            days.append(day)
        }
        let duration = days.reduce(0) { $0 + $1.durationSeconds }
        return TrainingWeek(
            weekStart: LocalDay.string(from: monday, calendar: calendar),
            days: days,
            count: days.reduce(0) { $0 + $1.count },
            durationSeconds: duration,
            distanceMeters: days.reduce(0) { $0 + $1.distanceMeters },
            trainingLoad: days.reduce(0) { $0 + $1.trainingLoad },
            elevationGain: (duration / 3600 * 70).rounded(),
            previousWeekCount: 5,
            previousWeekDurationSeconds: 5.6 * 3600,
            previousWeekTrainingLoad: 640,
            hrZoneSeconds: duration > 0 ? [0.18, 0.56, 0.14, 0.09, 0.03].map { ($0 * duration).rounded() } : [],
            sports: sports.values.sorted { $0.durationSeconds > $1.durationSeconds }
        )
    }

    private static func plan(from now: Date, calendar: Calendar, didWorkoutToday: Bool) -> [PlannedWorkout] {
        let today = calendar.startOfDay(for: now)
        let planName = String(localized: "Semi-marathon · Garmin Coach")
        return (0..<7).compactMap { offset -> PlannedWorkout? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let day = LocalDay.string(from: date, calendar: calendar)
            guard let workout = block.first(where: { $0.weekday == mondayIndex(date, calendar) }) else {
                return PlannedWorkout(date: day, name: String(localized: "Repos"), planName: planName, isRestDay: true, isRace: false, completed: false)
            }
            return PlannedWorkout(
                date: day, name: workout.name, sport: workout.sport, intent: workout.intent,
                durationSeconds: workout.minutes * 60, distanceMeters: workout.km > 0 ? workout.km * 1000 : nil,
                planName: planName, isRestDay: false, isRace: false, completed: offset == 0 && didWorkoutToday
            )
        }
    }
}

/// SplitMix64: tiny deterministic generator for reproducible demo curves.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
