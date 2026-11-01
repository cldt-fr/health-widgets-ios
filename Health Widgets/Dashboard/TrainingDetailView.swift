import SwiftUI
import WidgetKit

/// Full-screen version of a training widget, with everything that doesn't fit in it.
struct TrainingDetailView: View {
    var kind: TrainingKind

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot {
                VStack(spacing: 16) {
                    TrainingWidgetView(kind: kind, entry: HealthEntry(date: .now, snapshot: snapshot), family: .systemMedium)
                        .padding(18)
                        .frame(height: 190)
                        .cardSurface(tint: kind.colors[0])
                    details(snapshot)
                    DetailSection(title: "Comprendre") {
                        Text(kind.explanation)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .background(AuroraBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func details(_ snapshot: DashboardSnapshot) -> some View {
        switch kind {
        case .load: loadDetails(snapshot)
        case .week: weekDetails(snapshot)
        case .recovery: recoveryDetails(snapshot)
        case .predictions: predictionDetails(snapshot)
        case .plan: planDetails(snapshot)
        }
    }

    // MARK: Load

    @ViewBuilder
    private func loadDetails(_ snapshot: DashboardSnapshot) -> some View {
        if let status = snapshot.trainingStatus {
            DetailSection(title: "Charge") {
                StatGrid(stats: loadStats(status))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let focus = status.loadFocus {
                DetailSection(title: "Équilibre sur 4 semaines") {
                    VStack(alignment: .leading, spacing: 10) {
                        LoadFocusBars(focus: focus)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(width: 18, height: 8)
                            Text("Plage cible pour votre niveau")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let feedback = GarminTerms.label(focus.feedback) {
                            Text(feedback)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(kind.gradient)
                        }
                    }
                }
            }
        }
    }

    private func loadStats(_ status: TrainingStatusMetric) -> [MetricReading.Stat] {
        var stats: [MetricReading.Stat] = []
        if let acute = status.acuteLoad { stats.append(.init(label: String(localized: "Charge aiguë (7 j)"), value: Fmt.integer(acute))) }
        if let chronic = status.chronicLoad { stats.append(.init(label: String(localized: "Charge chronique (28 j)"), value: Fmt.integer(chronic))) }
        if let low = status.optimalLoadMin, let high = status.optimalLoadMax {
            stats.append(.init(label: String(localized: "Plage optimale"), value: "\(Fmt.integer(low))–\(Fmt.integer(high))"))
        }
        if let ratio = status.loadRatio {
            let state = GarminTerms.label(status.acwrStatus).map { " · \($0)" } ?? ""
            stats.append(.init(label: String(localized: "Ratio aiguë/chronique"), value: Fmt.decimal(ratio) + state))
        }
        if let label = GarminTerms.label(status.status) { stats.append(.init(label: String(localized: "Statut"), value: label)) }
        if let vo2 = status.vo2Max { stats.append(.init(label: "VO₂ max", value: Fmt.integer(vo2))) }
        return stats
    }

    // MARK: Week

    @ViewBuilder
    private func weekDetails(_ snapshot: DashboardSnapshot) -> some View {
        if let week = snapshot.trainingWeek {
            let imperial = snapshot.usesImperialUnits
            DetailSection(title: "Jour par jour") {
                VStack(spacing: 10) {
                    ForEach(week.days, id: \.date) { day in
                        HStack(spacing: 10) {
                            Text(day.day.map { $0.formatted(.dateTime.weekday(.wide)) }?.capitalized(with: .current) ?? day.date)
                                .font(.system(.subheadline, design: .rounded).weight(day.date == snapshot.calendarDate ? .bold : .regular))
                                .frame(width: 92, alignment: .leading)
                            HStack(spacing: 4) {
                                ForEach(Array(day.sports.enumerated()), id: \.offset) { _, sport in
                                    Image(systemName: GarminTerms.activitySymbol(sport))
                                        .foregroundStyle(ActivityStyle(sport).gradient)
                                }
                            }
                            Spacer()
                            if day.count > 0 {
                                Text(Fmt.duration(seconds: day.durationSeconds)).monospacedDigit()
                                Text(day.distanceMeters > 0 ? Fmt.distance(meters: day.distanceMeters, imperial: imperial) : "")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 74, alignment: .trailing)
                            } else {
                                Text(day.date > snapshot.calendarDate ? "–" : String(localized: "Repos"))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
            if !week.sports.isEmpty {
                DetailSection(title: "Par sport") {
                    VStack(spacing: 10) {
                        ForEach(week.sports, id: \.type) { sport in
                            HStack(spacing: 10) {
                                Image(systemName: GarminTerms.activitySymbol(sport.type))
                                    .foregroundStyle(ActivityStyle(sport.type).gradient)
                                    .frame(width: 22)
                                Text(GarminTerms.activityName(sport.type))
                                Text("× \(sport.count)").foregroundStyle(.secondary)
                                Spacer()
                                Text(Fmt.duration(seconds: sport.durationSeconds)).monospacedDigit()
                                Text(sport.distanceMeters > 0 ? Fmt.distance(meters: sport.distanceMeters, imperial: imperial) : "")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 74, alignment: .trailing)
                            }
                            .font(.system(.subheadline, design: .rounded))
                        }
                    }
                }
            }
            if !week.hrZoneSeconds.isEmpty {
                DetailSection(title: "Zones de fréquence cardiaque") {
                    VStack(alignment: .leading, spacing: 12) {
                        HRZonesBar(seconds: week.hrZoneSeconds, height: 12)
                        let total = max(week.hrZoneSeconds.reduce(0, +), 1)
                        ForEach(Array(week.hrZoneSeconds.enumerated()), id: \.offset) { index, seconds in
                            HStack {
                                Circle().fill(Palette.hrZones[index]).frame(width: 9, height: 9)
                                Text("Zone \(index + 1)")
                                Spacer()
                                Text(Fmt.duration(seconds: seconds)).monospacedDigit()
                                Text("\(Int((seconds / total * 100).rounded())) %")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(.system(.subheadline, design: .rounded))
                        }
                    }
                }
            }
            if let previous = week.previousWeekDurationSeconds {
                DetailSection(title: "Semaine dernière") {
                    StatGrid(stats: [
                        .init(label: String(localized: "Durée"), value: Fmt.duration(seconds: previous)),
                        .init(label: String(localized: "Séances"), value: Fmt.integer(week.previousWeekCount)),
                        .init(label: String(localized: "Charge"), value: Fmt.integer(week.previousWeekTrainingLoad)),
                        .init(label: String(localized: "Cette semaine"), value: Fmt.integer(week.trainingLoad)),
                    ])
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Recovery

    @ViewBuilder
    private func recoveryDetails(_ snapshot: DashboardSnapshot) -> some View {
        if let state = RecoveryState.make(snapshot) {
            DetailSection(title: "Récupération") {
                StatGrid(stats: [
                    .init(label: String(localized: "Temps restant"), value: state.isRecovered ? String(localized: "Terminée") : state.remainingText),
                    .init(label: String(localized: "Fin prévue"), value: state.until.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "–"),
                    .init(label: String(localized: "Disposition"), value: state.readinessScore.map(String.init) ?? "–"),
                    .init(label: String(localized: "Niveau"), value: GarminTerms.label(state.readinessLevel) ?? "–"),
                ])
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let factors = snapshot.trainingReadiness?.factors, !factors.isEmpty {
            DetailSection(title: "Facteurs de disposition") {
                FactorBars(factors: factors, colors: kind.colors)
            }
        }
    }

    // MARK: Predictions

    @ViewBuilder
    private func predictionDetails(_ snapshot: DashboardSnapshot) -> some View {
        if let predictions = snapshot.racePredictions {
            DetailSection(title: "Temps et allures") {
                VStack(spacing: 12) {
                    ForEach(RaceDistance.allCases, id: \.self) { distance in
                        if let seconds = distance.seconds(in: predictions) {
                            HStack {
                                Image(systemName: "flag.checkered").foregroundStyle(kind.gradient)
                                Text(distance.label)
                                Spacer()
                                Text(Fmt.clock(seconds: Double(seconds)))
                                    .font(.metric(18, weight: .semibold))
                                    .monospacedDigit()
                                Text(Fmt.pace(metersPerSecond: distance.meters / Double(seconds), imperial: snapshot.usesImperialUnits))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .trailing)
                            }
                            .font(.system(.subheadline, design: .rounded))
                        }
                    }
                }
            }
        }
    }

    // MARK: Plan

    @ViewBuilder
    private func planDetails(_ snapshot: DashboardSnapshot) -> some View {
        if snapshot.upcomingWorkouts.isEmpty {
            DetailSection(title: "À venir") {
                Text("Aucune séance planifiée. Ajoutez des séances à votre calendrier ou suivez un plan Garmin Coach dans Garmin Connect : elles apparaîtront ici et sur vos widgets.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else {
            DetailSection(title: LocalizedStringKey(snapshot.upcomingWorkouts.compactMap(\.planName).first ?? String(localized: "À venir"))) {
                VStack(spacing: 14) {
                    ForEach(snapshot.upcomingWorkouts) { workout in
                        PlannedWorkoutRow(workout: workout, imperial: snapshot.usesImperialUnits)
                    }
                }
            }
        }
    }
}

struct PlannedWorkoutRow: View {
    var workout: PlannedWorkout
    var imperial: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: workout.isRestDay ? [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)] : ActivityStyle(workout.sport ?? "").colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: workout.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workout.dayLabel)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                    if workout.completed {
                        Label("Faite", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingKind.recovery.colors[0])
                    }
                }
                Text(workout.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(workout.isRestDay ? .secondary : .primary)
                let details = [workout.durationSeconds.map { Fmt.duration(seconds: $0) }, workout.distanceMeters.map { Fmt.distance(meters: $0, imperial: imperial) }, GarminTerms.label(workout.intent)].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
