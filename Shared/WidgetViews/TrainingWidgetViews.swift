import SwiftUI
import WidgetKit

// MARK: - Building blocks

/// Uppercase caption with the training widget's gradient glyph.
struct TrainingTitle: View {
    var kind: TrainingKind
    var compact = false
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(kind.gradient)
                .widgetAccentable()
            Text(compact ? kind.shortTitle : kind.title)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Acute load on a track, with Garmin's optimal range highlighted.
struct LoadRangeGauge: View {
    var acute: Double
    var low: Double?
    var high: Double?
    var height: CGFloat = 8

    @Environment(\.widgetRenderingMode) private var renderingMode

    static func color(acute: Double, low: Double?, high: Double?) -> Color {
        guard let low, let high else { return TrainingKind.load.colors[0] }
        if acute < low { return Color(hex: 0x3D8BFF) }
        if acute > high { return Color(hex: 0xFF4D6D) }
        return Color(hex: 0x14D68C)
    }

    var body: some View {
        GeometryReader { proxy in
            let upper = max((high ?? acute) * 1.35, acute * 1.1, 1)
            let x = { (value: Double) in proxy.size.width * CGFloat(min(max(value / upper, 0), 1)) }
            let fullColor = renderingMode == .fullColor
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: height)
                if let low, let high {
                    Capsule()
                        .fill(fullColor ? Color(hex: 0x14D68C).opacity(0.45) : Color.primary.opacity(0.35))
                        .frame(width: max(x(high) - x(low), height), height: height)
                        .offset(x: x(low))
                        .widgetAccentable()
                }
                Circle()
                    .fill(fullColor ? Self.color(acute: acute, low: low, high: high) : Color.primary)
                    .frame(width: height * 2, height: height * 2)
                    .overlay(Circle().stroke(Color.white.opacity(fullColor ? 0.9 : 0), lineWidth: 2))
                    .shadow(color: fullColor ? Self.color(acute: acute, low: low, high: high).opacity(0.6) : .clear, radius: 5)
                    .offset(x: x(acute) - height)
                    .widgetAccentable()
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height * 2)
        .accessibilityHidden(true)
    }
}

/// Garmin's 4-week load focus: value against its target band, per intensity.
struct LoadFocusBars: View {
    var focus: LoadFocus
    var compact = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let rows: [(String, LoadFocusPart?, Color)] = [
            (String(localized: "Aérobie légère"), focus.aerobicLow, Palette.loadFocus[0]),
            (String(localized: "Aérobie intense"), focus.aerobicHigh, Palette.loadFocus[1]),
            (String(localized: "Anaérobie"), focus.anaerobic, Palette.loadFocus[2]),
        ]
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            ForEach(rows, id: \.0) { title, part, color in
                if let part, let value = part.value {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(title)
                            Spacer()
                            Text(Fmt.integer(value)).monospacedDigit()
                        }
                        .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                        bar(value: value, part: part, color: color)
                    }
                }
            }
        }
    }

    private func bar(value: Double, part: LoadFocusPart, color: Color) -> some View {
        GeometryReader { proxy in
            let upper = max((part.targetMax ?? value) * 1.25, value * 1.05, 1)
            let x = { (v: Double) in proxy.size.width * CGFloat(min(max(v / upper, 0), 1)) }
            let fullColor = renderingMode == .fullColor
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let low = part.targetMin, let high = part.targetMax {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: max(x(high) - x(low), 4))
                        .offset(x: x(low))
                }
                Capsule()
                    .fill(fullColor ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary))
                    .frame(width: max(x(value), 4))
                    .widgetAccentable()
            }
        }
        .frame(height: compact ? 5 : 7)
    }
}

/// Seven days, Monday to Sunday: one bar per day, split by sport.
struct WeekBars: View {
    var week: TrainingWeek
    var today: String
    var showsLabels = true

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let longest = max(week.days.map(\.durationSeconds).max() ?? 0, 3600)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(week.days, id: \.date) { day in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack(spacing: 1.5) {
                            Spacer(minLength: 0)
                            if day.count == 0 {
                                Circle()
                                    .fill(Color.primary.opacity(day.date > today ? 0.08 : 0.2))
                                    .frame(width: 4, height: 4)
                                    .frame(maxWidth: .infinity)
                            } else {
                                let share = proxy.size.height * day.durationSeconds / longest / Double(max(day.sports.count, 1))
                                ForEach(Array(day.sports.enumerated()), id: \.offset) { _, sport in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(renderingMode == .fullColor
                                            ? AnyShapeStyle(LinearGradient(colors: ActivityStyle(sport).colors, startPoint: .bottom, endPoint: .top))
                                            : AnyShapeStyle(Color.primary))
                                        .frame(height: max(4, share - 1.5))
                                        .widgetAccentable()
                                }
                            }
                        }
                    }
                    if showsLabels {
                        Text(Fmt.weekday(day.date))
                            .font(.system(size: 9, weight: day.date == today ? .heavy : .semibold, design: .rounded))
                            .foregroundStyle(day.date == today ? .primary : .secondary)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Time in heart-rate zones 1–5 as one segmented capsule.
struct HRZonesBar: View {
    var seconds: [Double]
    var height: CGFloat = 7

    static func easyShare(_ seconds: [Double]) -> Int? {
        let total = seconds.reduce(0, +)
        guard total > 0, seconds.count >= 2 else { return nil }
        return Int(((seconds[0] + seconds[1]) / total * 100).rounded())
    }

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(Array(seconds.prefix(5).enumerated()), id: \.offset) { index, value in
                    if value > 0 {
                        Capsule()
                            .fill(Palette.hrZones[index])
                            .frame(width: max(height * 0.6, (proxy.size.width - 6) * value / total))
                    }
                }
            }
        }
        .frame(height: height)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

struct TrainingEmptyView: View {
    var kind: TrainingKind
    var family: WidgetFamily
    var message: String

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: kind.symbol).font(.title3)
            }
        case .accessoryInline:
            Label(kind.shortTitle, systemImage: kind.symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(kind.title, systemImage: kind.symbol).font(.headline)
                Text(message).font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                TrainingTitle(kind: kind, compact: family == .systemSmall)
                Spacer(minLength: 0)
                Image(systemName: kind.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(kind.gradient)
                Text(message)
                    .font(.metric(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Training load

struct TrainingLoadView: View {
    var snapshot: DashboardSnapshot
    var family: WidgetFamily

    private let kind = TrainingKind.load

    var body: some View {
        if let status = snapshot.trainingStatus, let acute = status.acuteLoad {
            switch family {
            case .accessoryRectangular: rectangular(status, acute)
            case .accessoryCircular: circular(status, acute)
            case .accessoryInline:
                Label("Charge \(Fmt.integer(acute)) · \(label(status))", systemImage: kind.symbol)
            case .systemMedium, .systemLarge, .systemExtraLarge: medium(status, acute)
            default: small(status, acute)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: String(localized: "Pas encore de charge : synchronisez une activité"))
        }
    }

    private func label(_ status: TrainingStatusMetric) -> String {
        GarminTerms.label(status.status) ?? GarminTerms.label(status.acwrStatus) ?? String(localized: "Charge aiguë")
    }

    private func rangeText(_ status: TrainingStatusMetric) -> String? {
        guard let low = status.optimalLoadMin, let high = status.optimalLoadMax else { return nil }
        return String(localized: "Optimale \(Fmt.integer(low))–\(Fmt.integer(high))")
    }

    private func small(_ status: TrainingStatusMetric, _ acute: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TrainingTitle(kind: kind, compact: true)
            Spacer(minLength: 4)
            ValueLabel(value: Fmt.integer(acute), size: 40)
            Text(label(status))
                .font(.metric(12, weight: .semibold))
                .foregroundStyle(kind.gradient)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 8)
            LoadRangeGauge(acute: acute, low: status.optimalLoadMin, high: status.optimalLoadMax)
            if let range = rangeText(status) {
                Text(range)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ status: TrainingStatusMetric, _ acute: Double) -> some View {
        HStack(alignment: .top, spacing: 18) {
            small(status, acute)
                .frame(width: 128)
            VStack(alignment: .leading, spacing: 8) {
                Text("Équilibre sur 4 semaines")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let focus = status.loadFocus {
                    LoadFocusBars(focus: focus, compact: true)
                    Spacer(minLength: 0)
                    if let feedback = GarminTerms.label(focus.feedback) {
                        Text(feedback)
                            .font(.metric(11, weight: .semibold))
                            .foregroundStyle(kind.gradient)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                } else {
                    StatGrid(stats: [
                        .init(label: String(localized: "Charge chronique"), value: Fmt.integer(status.chronicLoad)),
                        .init(label: String(localized: "Ratio"), value: Fmt.decimal(status.loadRatio)),
                    ])
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rectangular(_ status: TrainingStatusMetric, _ acute: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol).widgetAccentable()
                Text(kind.shortTitle).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ValueLabel(value: Fmt.integer(acute), size: 24)
                Text(label(status))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            LoadRangeGauge(acute: acute, low: status.optimalLoadMin, high: status.optimalLoadMax, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circular(_ status: TrainingStatusMetric, _ acute: Double) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            RingGauge(progress: min((status.loadRatio ?? 1) / 2, 1), colors: kind.colors, lineWidth: 5)
                .padding(2.5)
            VStack(spacing: -2) {
                Text("ACWR").font(.system(size: 8, weight: .bold, design: .rounded))
                Text(Fmt.decimal(status.loadRatio))
                    .font(.metric(17))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

// MARK: - Training week

struct TrainingWeekView: View {
    var snapshot: DashboardSnapshot
    var family: WidgetFamily

    private let kind = TrainingKind.week

    var body: some View {
        if let week = snapshot.trainingWeek {
            switch family {
            case .systemMedium, .systemLarge, .systemExtraLarge: medium(week)
            case .accessoryRectangular: rectangular(week)
            case .accessoryInline:
                Label("\(Fmt.duration(seconds: week.durationSeconds)) · \(sessions(week.count))", systemImage: kind.symbol)
            default: small(week)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: String(localized: "Semaine indisponible pour le moment"))
        }
    }

    private func sessions(_ count: Int) -> String {
        count == 1 ? String(localized: "1 séance") : String(localized: "\(count) séances")
    }

    private var imperial: Bool { snapshot.usesImperialUnits }

    private func headline(_ week: TrainingWeek) -> String {
        week.durationSeconds > 0 ? Fmt.duration(seconds: week.durationSeconds) : "0 min"
    }

    private func subtitle(_ week: TrainingWeek) -> String {
        week.distanceMeters > 0
            ? "\(sessions(week.count)) · \(Fmt.distance(meters: week.distanceMeters, imperial: imperial))"
            : sessions(week.count)
    }

    private func comparison(_ week: TrainingWeek) -> String? {
        guard let previous = week.previousWeekDurationSeconds, previous > 0 else { return nil }
        return String(localized: "Sem. dernière \(Fmt.duration(seconds: previous))")
    }

    private func small(_ week: TrainingWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TrainingTitle(kind: kind, compact: true)
            Spacer(minLength: 4)
            ValueLabel(value: headline(week), size: 34)
            Text(subtitle(week))
                .font(.metric(11, weight: .semibold))
                .foregroundStyle(kind.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            Spacer(minLength: 6)
            WeekBars(week: week, today: snapshot.calendarDate, showsLabels: false)
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ week: TrainingWeek) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                TrainingTitle(kind: kind, compact: true)
                Spacer(minLength: 4)
                ValueLabel(value: headline(week), size: 34)
                Text(subtitle(week))
                    .font(.metric(11, weight: .semibold))
                    .foregroundStyle(kind.gradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                if let comparison = comparison(week) {
                    Text(comparison)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 6)
                if !week.hrZoneSeconds.isEmpty {
                    HRZonesBar(seconds: week.hrZoneSeconds, height: 6)
                    if let easy = HRZonesBar.easyShare(week.hrZoneSeconds) {
                        Text("Zones 1–2 : \(easy) %")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                }
            }
            .frame(width: 128, alignment: .leading)
            WeekBars(week: week, today: snapshot.calendarDate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rectangular(_ week: TrainingWeek) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol).widgetAccentable()
                Text(kind.shortTitle).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ValueLabel(value: headline(week), size: 22)
                Text(sessions(week.count))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            WeekBars(week: week, today: snapshot.calendarDate, showsLabels: false)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recovery

struct RecoveryView: View {
    var snapshot: DashboardSnapshot
    var family: WidgetFamily
    /// The timeline entry's date: the countdown advances without a network refresh.
    var now: Date = .now

    private let kind = TrainingKind.recovery

    var body: some View {
        if let state = RecoveryState.make(snapshot, at: now) {
            switch family {
            case .accessoryCircular: circular(state)
            case .accessoryRectangular: rectangular(state)
            case .accessoryInline:
                Label(state.isRecovered ? String(localized: "Récupération terminée") : String(localized: "Récupéré dans \(state.remainingText)"), systemImage: kind.symbol)
            case .systemMedium, .systemLarge, .systemExtraLarge: medium(state)
            default: small(state)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: String(localized: "Disposition à l'entraînement indisponible sur cette montre"))
        }
    }

    private func ring(_ state: RecoveryState, lineWidth: CGFloat, valueSize: CGFloat) -> some View {
        ZStack {
            RingGauge(progress: state.progress, colors: kind.colors, lineWidth: lineWidth)
            VStack(spacing: 0) {
                if state.isRecovered {
                    Image(systemName: "checkmark")
                        .font(.system(size: valueSize * 0.8, weight: .heavy))
                        .foregroundStyle(kind.gradient)
                        .widgetAccentable()
                    Text("Prêt")
                        .font(.metric(valueSize * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.remainingText)
                        .font(.metric(valueSize))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("restantes")
                        .font(.metric(valueSize * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(lineWidth * 1.3)
        }
    }

    private func untilText(_ state: RecoveryState) -> String? {
        guard let until = state.until, !state.isRecovered else { return nil }
        let calendar = Calendar.current
        let time = until.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(until) { return String(localized: "Jusqu'à \(time)") }
        if calendar.isDateInTomorrow(until) { return String(localized: "Jusqu'à demain \(time)") }
        return String(localized: "Jusqu'à \(until.formatted(.dateTime.weekday(.abbreviated))) \(time)")
    }

    private func small(_ state: RecoveryState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TrainingTitle(kind: kind, compact: true)
            ring(state, lineWidth: 12, valueSize: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(untilText(state) ?? state.advice)
                .font(.metric(11, weight: .semibold))
                .foregroundStyle(kind.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetAccentable()
        }
    }

    private func medium(_ state: RecoveryState) -> some View {
        HStack(spacing: 16) {
            ring(state, lineWidth: 13, valueSize: 30)
                .frame(width: 116)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                TrainingTitle(kind: kind)
                Text(state.advice)
                    .font(.metric(16))
                    .foregroundStyle(kind.gradient)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                if let until = untilText(state) {
                    Text(until)
                        .font(.metric(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                StatGrid(stats: contributors)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contributors: [MetricReading.Stat] {
        var stats: [MetricReading.Stat] = []
        if let readiness = snapshot.trainingReadiness, let score = readiness.score {
            stats.append(.init(label: String(localized: "Disposition"), value: "\(score) · \(GarminTerms.label(readiness.level) ?? "")"))
        }
        if let hrv = snapshot.hrv?.lastNightAvg {
            stats.append(.init(label: String(localized: "VFC"), value: "\(hrv) ms"))
        }
        if let sleep = snapshot.sleep?.score {
            stats.append(.init(label: String(localized: "Sommeil"), value: "\(sleep)"))
        }
        if let battery = snapshot.bodyBattery?.current {
            stats.append(.init(label: String(localized: "Énergie"), value: "\(battery)"))
        }
        return Array(stats.prefix(4))
    }

    private func circular(_ state: RecoveryState) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            RingGauge(progress: state.progress, colors: kind.colors, lineWidth: 5)
                .padding(2.5)
            VStack(spacing: -2) {
                Image(systemName: state.isRecovered ? "checkmark" : kind.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .widgetAccentable()
                Text(state.isRecovered ? String(localized: "Prêt") : state.remainingText.replacingOccurrences(of: " ", with: ""))
                    .font(.metric(15))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(6)
        }
    }

    private func rectangular(_ state: RecoveryState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol).widgetAccentable()
                Text(kind.title).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            Text(state.isRecovered ? state.advice : String(localized: "\(state.remainingText) restantes"))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Gauge(value: state.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Race predictions

struct RacePredictionsWidgetView: View {
    var snapshot: DashboardSnapshot
    var family: WidgetFamily
    var distance: RaceDistance = .tenK

    private let kind = TrainingKind.predictions

    var body: some View {
        if let predictions = snapshot.racePredictions, distance.seconds(in: predictions) != nil || family == .systemMedium {
            switch family {
            case .systemMedium, .systemLarge, .systemExtraLarge: medium(predictions)
            case .accessoryRectangular: rectangular(predictions)
            case .accessoryInline:
                Label("\(distance.label) \(time(predictions, distance))", systemImage: kind.symbol)
            default: small(predictions)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: String(localized: "Pas encore de prédiction : courez avec votre montre"))
        }
    }

    private var imperial: Bool { snapshot.usesImperialUnits }

    private func time(_ predictions: RacePredictions, _ distance: RaceDistance) -> String {
        Fmt.clock(seconds: distance.seconds(in: predictions).map(Double.init))
    }

    private func pace(_ predictions: RacePredictions, _ distance: RaceDistance) -> String {
        guard let seconds = distance.seconds(in: predictions), seconds > 0 else { return "–" }
        return Fmt.pace(metersPerSecond: distance.meters / Double(seconds), imperial: imperial)
    }

    @ViewBuilder private var vo2Chip: some View {
        if let vo2 = snapshot.trainingStatus?.vo2Max {
            Text("VO₂ max \(Fmt.integer(vo2))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(kind.colors[0].opacity(0.18)))
                .foregroundStyle(kind.gradient)
        }
    }

    private func small(_ predictions: RacePredictions) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TrainingTitle(kind: kind, compact: true)
            Spacer(minLength: 4)
            Text(distance.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(time(predictions, distance))
                .font(.metric(34))
                .monospacedDigit()
                .foregroundStyle(kind.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(pace(predictions, distance))
                .font(.metric(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            vo2Chip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ predictions: RacePredictions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TrainingTitle(kind: kind)
                Spacer()
                vo2Chip
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(predictions, .fiveK)
                    tile(predictions, .tenK)
                }
                GridRow {
                    tile(predictions, .half)
                    tile(predictions, .marathon)
                }
            }
        }
    }

    private func tile(_ predictions: RacePredictions, _ distance: RaceDistance) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(distance.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(time(predictions, distance))
                .font(.metric(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(pace(predictions, distance))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func rectangular(_ predictions: RacePredictions) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol).widgetAccentable()
                Text(distance.label).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(time(predictions, distance))
                .font(.metric(24))
                .monospacedDigit()
            Text(pace(predictions, distance))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next workout

struct NextWorkoutView: View {
    var snapshot: DashboardSnapshot
    var family: WidgetFamily

    private let kind = TrainingKind.plan

    var body: some View {
        if let workout = snapshot.nextWorkout {
            switch family {
            case .systemMedium, .systemLarge, .systemExtraLarge: medium(workout)
            case .accessoryRectangular: rectangular(workout)
            case .accessoryInline:
                Label("\(workout.dayLabel) : \(workout.title)", systemImage: workout.symbol)
            default: small(workout)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: suggestion)
        }
    }

    /// Without a plan: what readiness suggests for today.
    private var suggestion: String {
        guard let state = RecoveryState.make(snapshot) else {
            return String(localized: "Aucune séance planifiée")
        }
        return String(localized: "Aucune séance planifiée · \(state.advice.lowercased())")
    }

    private var imperial: Bool { snapshot.usesImperialUnits }

    private func details(_ workout: PlannedWorkout) -> String? {
        var parts: [String] = []
        if let duration = workout.durationSeconds { parts.append(Fmt.duration(seconds: duration)) }
        if let distance = workout.distanceMeters { parts.append(Fmt.distance(meters: distance, imperial: imperial)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func badge(_ workout: PlannedWorkout, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(LinearGradient(colors: workout.isRestDay ? kind.colors : ActivityStyle(workout.sport ?? "").colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: workout.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .widgetAccentable()
    }

    private func small(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                badge(workout, size: 32)
                Spacer()
                Text(workout.dayLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.gradient)
                    .widgetAccentable()
            }
            Spacer(minLength: 2)
            Text(workout.title)
                .font(.metric(16))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let details = details(workout) {
                Text(details)
                    .font(.metric(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let intent = GarminTerms.label(workout.intent),
               intent.compare(workout.title, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                Text(intent)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(kind.colors[0].opacity(0.18)))
                    .foregroundStyle(kind.gradient)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ workout: PlannedWorkout) -> some View {
        let following = snapshot.upcomingWorkouts
            .filter { $0.date > workout.date || ($0.date == workout.date && $0.id != workout.id && !$0.isRestDay) }
            .prefix(3)
        return HStack(alignment: .top, spacing: 16) {
            small(workout)
                .frame(width: 126)
            VStack(alignment: .leading, spacing: 7) {
                Text(workout.planName ?? String(localized: "À venir"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ForEach(Array(following)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                            .foregroundStyle(item.isRestDay ? AnyShapeStyle(.tertiary) : AnyShapeStyle(LinearGradient(colors: ActivityStyle(item.sport ?? "").colors, startPoint: .leading, endPoint: .trailing)))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(item.isRestDay ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text([item.day.map { $0.formatted(.dateTime.weekday(.wide)) }?.capitalized(with: .current), item.durationSeconds.map { Fmt.duration(seconds: $0) }].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rectangular(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: workout.symbol).widgetAccentable()
                Text(workout.dayLabel).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(workout.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let details = details(workout) {
                Text(details)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dispatch

/// One entry point for every training widget (the app's gallery and cards use it too).
struct TrainingWidgetView: View {
    var kind: TrainingKind
    var entry: HealthEntry
    var family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot {
            switch kind {
            case .load: TrainingLoadView(snapshot: snapshot, family: family)
            case .week: TrainingWeekView(snapshot: snapshot, family: family)
            case .recovery: RecoveryView(snapshot: snapshot, family: family, now: entry.date)
            case .predictions: RacePredictionsWidgetView(snapshot: snapshot, family: family, distance: entry.raceDistance)
            case .plan: NextWorkoutView(snapshot: snapshot, family: family)
            }
        } else {
            TrainingEmptyView(kind: kind, family: family, message: entry.message ?? String(localized: "Pas encore de données"))
        }
    }
}
