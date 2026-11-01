import Charts
import SwiftUI

struct MetricDetailView: View {
    var kind: MetricKind

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot, let reading = snapshot.reading(kind) {
                VStack(spacing: 16) {
                    hero(reading)
                    charts(reading, snapshot)
                    if !reading.stats.isEmpty {
                        DetailSection(title: "Détails") {
                            StatGrid(stats: reading.stats)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if kind == .readiness, let factors = snapshot.trainingReadiness?.factors, !factors.isEmpty {
                        DetailSection(title: "Facteurs") {
                            FactorBars(factors: factors, colors: kind.colors)
                        }
                    }
                    if kind == .vo2Max, let predictions = snapshot.racePredictions {
                        DetailSection(title: "Prédictions de course") {
                            RacePredictionsView(predictions: predictions)
                        }
                    }
                    DetailSection(title: "Comprendre") {
                        Text(Self.explanation(kind))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView(kind.title, systemImage: kind.symbol, description: Text("Pas de données pour aujourd'hui."))
                    .padding(.top, 100)
            }
        }
        .background(AuroraBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ reading: MetricReading) -> some View {
        VStack(spacing: 14) {
            if reading.progress != nil {
                RingValue(reading: reading, lineWidth: 18, valueSize: 54)
                    .frame(width: 210, height: 210)
            } else {
                MetricBadge(kind: kind, size: 64)
                ValueLabel(value: reading.value, unit: reading.unit, size: 64)
            }
            if let label = reading.label {
                Text(label)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.gradient)
            }
            if let detail = reading.detail {
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .cardSurface(tint: kind.tint)
    }

    @ViewBuilder
    private func charts(_ reading: MetricReading, _ snapshot: DashboardSnapshot) -> some View {
        if kind == .sleep, let sleep = snapshot.sleep, !sleep.stages.isEmpty {
            DetailSection(title: "Phases de la nuit") {
                VStack(alignment: .leading, spacing: 12) {
                    HypnogramChart(stages: sleep.stages, showsAxis: true)
                        .frame(height: 150)
                    SleepStagesBar(sleep: sleep, height: 10)
                    SleepLegend(sleep: sleep)
                }
            }
        }
        if !reading.series.isEmpty {
            DetailSection(title: kind == .hrv ? "Mesures de la nuit" : "Aujourd'hui") {
                DetailSeriesChart(points: reading.series, colors: kind.colors, domain: reading.seriesDomain)
                    .frame(height: 180)
            }
        }
        if reading.history.count > 1 {
            DetailSection(title: "7 derniers jours") {
                HistoryBars(values: reading.history, colors: kind.colors, goal: reading.historyGoal)
                    .frame(height: 140)
            }
        }
    }

    static func explanation(_ kind: MetricKind) -> String {
        switch kind {
        case .bodyBattery:
            String(localized: "Le Body Battery estime votre réserve d'énergie de 0 à 100 à partir de la VFC, du stress, du sommeil et de l'activité. Il se recharge au repos et se vide avec l'effort et le stress.")
        case .sleep:
            String(localized: "Le score de sommeil (0–100) combine la durée, la répartition des phases (profond, léger, paradoxal), les éveils et le stress nocturne.")
        case .readiness:
            String(localized: "La disposition à l'entraînement combine sommeil, temps de récupération, VFC, charge aiguë et historiques de sommeil et de stress pour indiquer si vous êtes prêt pour un effort intense.")
        case .hrv:
            String(localized: "La variabilité de la fréquence cardiaque, mesurée pendant la nuit, reflète l'équilibre de votre système nerveux. Comparez-la à votre plage habituelle plutôt qu'à celle des autres.")
        case .steps:
            String(localized: "Vos pas de la journée face à votre objectif, que Garmin ajuste automatiquement selon votre activité récente.")
        case .stress:
            String(localized: "Le stress (0–100) est estimé à partir de la VFC : 0–25 repos, 26–50 faible, 51–75 moyen, 76–100 élevé. Il n'est pas mesuré pendant les activités.")
        case .heartRate:
            String(localized: "Une fréquence cardiaque au repos qui baisse au fil des semaines traduit souvent une meilleure forme. Une hausse inhabituelle peut signaler fatigue, maladie ou manque de sommeil.")
        case .intensityMinutes:
            String(localized: "L'OMS recommande au moins 150 minutes d'activité modérée par semaine. Les minutes intenses comptent double.")
        case .calories:
            String(localized: "Les calories actives correspondent à votre activité physique ; les calories au repos à votre métabolisme de base.")
        case .vo2Max:
            String(localized: "Le VO₂ max estime votre consommation maximale d'oxygène pendant l'effort : c'est l'un des meilleurs indicateurs de votre endurance.")
        }
    }
}

struct DetailSection<Content: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Intraday curve with hour axis and value axis.
struct DetailSeriesChart: View {
    var points: [Point]
    var colors: [Color]
    var domain: ClosedRange<Double>?

    var body: some View {
        let values = points.map(\.v)
        let low = domain?.lowerBound ?? ((values.min() ?? 0) - 5)
        let high = domain?.upperBound ?? ((values.max() ?? 1) + 5)
        Chart(points, id: \.t) { point in
            AreaMark(x: .value("Heure", point.date), yStart: .value("Base", low), yEnd: .value("Valeur", point.v))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [colors[0].opacity(0.35), colors[0].opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Heure", point.date), y: .value("Valeur", point.v))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        }
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel()
            }
        }
    }
}

struct SleepLegend: View {
    var sleep: SleepMetric

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(SleepStage.allCases, id: \.self) { stage in
                HStack(spacing: 8) {
                    Circle().fill(Palette.color(for: stage)).frame(width: 9, height: 9)
                    Text(Palette.name(for: stage))
                        .font(.system(.subheadline, design: .rounded))
                    Spacer(minLength: 2)
                    Text(Fmt.duration(seconds: sleep.seconds(in: stage)))
                        .font(.metric(15, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
    }
}

struct RacePredictionsView: View {
    var predictions: RacePredictions

    var body: some View {
        let rows: [(String, Int?)] = [
            ("5 km", predictions.fiveK),
            ("10 km", predictions.tenK),
            (String(localized: "Semi-marathon"), predictions.halfMarathon),
            (String(localized: "Marathon"), predictions.marathon),
        ]
        VStack(spacing: 10) {
            ForEach(rows.filter { $0.1 != nil }, id: \.0) { label, seconds in
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(MetricKind.vo2Max.gradient)
                    Text(label).font(.system(.subheadline, design: .rounded))
                    Spacer()
                    Text(Fmt.clock(seconds: seconds.map(Double.init)))
                        .font(.metric(17, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Activity

struct ActivityDetailSheet: View {
    var activity: Activity
    var imperial: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        ActivityBadge(activity: activity, size: 64)
                        Text(activity.name ?? GarminTerms.activityName(activity.type))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        if let started = activity.startedAt {
                            Text(started, format: .dateTime.weekday(.wide).day().month().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                        Text(ActivityWidgetView.headline(activity, imperial: imperial))
                            .font(.metric(48))
                            .foregroundStyle(ActivityStyle(activity.type).gradient)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .cardSurface(tint: ActivityStyle(activity.type).colors[0])

                    DetailSection(title: "Séance") {
                        StatGrid(stats: Self.allStats(activity, imperial: imperial))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let aerobic = activity.aerobicEffect {
                        DetailSection(title: "Effet d'entraînement") {
                            TrainingEffectBar(aerobic: aerobic, anaerobic: activity.anaerobicEffect ?? 0, label: GarminTerms.label(activity.effectLabel))
                        }
                    }
                }
                .padding(16)
            }
            .background(AuroraBackground())
            .navigationTitle("Dernière activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    static func allStats(_ activity: Activity, imperial: Bool) -> [MetricReading.Stat] {
        var stats = ActivityWidgetView.stats(activity, imperial: imperial)
        if let max = activity.maxHr { stats.append(.init(label: String(localized: "FC max"), value: "\(max) bpm")) }
        if let load = activity.trainingLoad { stats.append(.init(label: String(localized: "Charge"), value: Fmt.integer(load))) }
        if let gain = activity.elevationGain, gain > 5, !stats.contains(where: { $0.label == "D+" }) {
            stats.append(.init(label: "D+", value: "\(Fmt.integer(gain)) m"))
        }
        if let vo2 = activity.vo2Max { stats.append(.init(label: "VO₂ max", value: Fmt.integer(vo2))) }
        return stats
    }
}

// MARK: - Reconnect

struct ReconnectGarminSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var challengeID: String?

    var body: some View {
        NavigationStack {
            Group {
                if let challengeID {
                    GarminCodeView(challengeID: challengeID) { finish() }
                } else {
                    GarminLoginView { step in
                        switch step {
                        case .connected: finish()
                        case .needsCode(let id): challengeID = id
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func finish() {
        dismiss()
        Task { await model.refresh(force: true) }
    }
}
