import SwiftUI
import WidgetKit

/// "Today": a live board of the same cards as the widgets, with zoom transitions into
/// each metric's detail.
struct DashboardView: View {
    enum Route: Hashable {
        case metric(MetricKind)
        case training(TrainingKind)
    }

    enum Section: String, CaseIterable, Identifiable {
        case health, training
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .health ? "Santé" : "Entraînement" }
    }

    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    @State private var path: [Route] = []
    @State private var showsReconnect = false
    @AppStorage("dashboardSection") private var section: Section = .health

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                if let snapshot = model.snapshot {
                    content(snapshot)
                } else if model.isRefreshing || model.isFirstSync {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        if model.isFirstSync {
                            Text("Première synchronisation avec Garmin…")
                                .font(.headline)
                            Text("Récupération de vos données du jour. Cela peut prendre jusqu'à 30 secondes.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 120)
                } else {
                    ContentUnavailableView {
                        Label("Pas encore de données", systemImage: "applewatch")
                    } description: {
                        Text(model.refreshError?.errorDescription ?? String(localized: "Synchronisez votre montre avec Garmin Connect, puis tirez pour actualiser."))
                    } actions: {
                        Button("Actualiser") { Task { await model.refresh(force: true) } }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 80)
                }
            }
            .debugScrollTarget(proxy)
            }
            .background(AuroraBackground())
            .refreshable { await model.refresh(force: true) }
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .metric(let kind): MetricDetailView(kind: kind)
                    case .training(let kind): TrainingDetailView(kind: kind)
                    }
                }
                .navigationTransition(.zoom(sourceID: route, in: zoom))
            }
            .sheet(isPresented: $showsReconnect) {
                ReconnectGarminSheet()
            }
            .sheet(isPresented: Bindable(model).showsLastActivity) {
                if let activity = model.snapshot?.lastActivity {
                    ActivityDetailSheet(activity: activity, imperial: model.snapshot?.usesImperialUnits ?? false)
                }
            }
            .onChange(of: model.focusedMetric, initial: true) { _, kind in
                guard let kind else { return }
                section = .health
                path = [.metric(kind)]
                model.focusedMetric = nil
            }
            .onChange(of: model.focusedTraining, initial: true) { _, kind in
                guard let kind else { return }
                section = .training
                path = [.training(kind)]
                model.focusedTraining = nil
            }
        }
    }

    private func content(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardHeader(snapshot: snapshot, isRefreshing: model.isRefreshing) {
                Task { await model.refresh(force: true) }
            }
            if let banner = Banner(snapshot: snapshot, error: model.refreshError) {
                StatusBanner(banner: banner) { showsReconnect = true }
            }

            DayRingsCard(snapshot: snapshot)
                .onTapGesture { path.append(.metric(.readiness)) }

            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)

            switch section {
            case .health: healthSection(snapshot)
            case .training: trainingSection(snapshot)
            }

            Text("Données \(snapshot.source.provider == "demo" ? String(localized: "de démonstration") : "Garmin Connect") · \((LocalDay.date(from: snapshot.calendarDate) ?? .now).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func healthSection(_ snapshot: DashboardSnapshot) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(gridMetrics(snapshot) + (moreMetrics(snapshot) ?? []), id: \.self) { kind in
                if let reading = snapshot.reading(kind) {
                    NavigationLink(value: Route.metric(kind)) {
                        SmallMetricView(reading: reading, snapshot: snapshot)
                            .padding(14)
                            .frame(height: 172)
                            .cardSurface(tint: kind.tint)
                            .contentShape(.rect(cornerRadius: 26))
                    }
                    .buttonStyle(CardButtonStyle())
                    .matchedTransitionSource(id: Route.metric(kind), in: zoom)
                }
            }
        }

        if let sleep = snapshot.reading(.sleep) {
            NavigationLink(value: Route.metric(.sleep)) {
                MediumMetricView(reading: sleep, snapshot: snapshot)
                    .padding(16)
                    .frame(height: 176)
                    .cardSurface(tint: MetricKind.sleep.tint)
                    .contentShape(.rect(cornerRadius: 26))
            }
            .buttonStyle(CardButtonStyle())
            .matchedTransitionSource(id: Route.metric(.sleep), in: zoom)
            .id("sleep")
        }
    }

    @ViewBuilder
    private func trainingSection(_ snapshot: DashboardSnapshot) -> some View {
        let entry = HealthEntry(date: DemoData.clock, snapshot: snapshot)
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach([TrainingKind.recovery, .load], id: \.self) { kind in
                trainingCard(kind, entry: entry, family: .systemSmall, height: 172)
            }
        }
        ForEach([TrainingKind.week, .plan, .predictions], id: \.self) { kind in
            trainingCard(kind, entry: entry, family: .systemMedium, height: 176)
        }
        if snapshot.lastActivity != nil {
            Button { model.showsLastActivity = true } label: {
                ActivityWidgetView(entry: entry, family: .systemMedium)
                    .padding(16)
                    .frame(height: 176)
                    .cardSurface(tint: ActivityStyle(snapshot.lastActivity?.type ?? "").colors[0])
                    .contentShape(.rect(cornerRadius: 26))
            }
            .buttonStyle(CardButtonStyle())
            .id("activity")
        }
    }

    private func trainingCard(_ kind: TrainingKind, entry: HealthEntry, family: WidgetFamily, height: CGFloat) -> some View {
        NavigationLink(value: Route.training(kind)) {
            TrainingWidgetView(kind: kind, entry: entry, family: family)
                .padding(family == .systemSmall ? 14 : 16)
                .frame(height: height)
                .cardSurface(tint: kind.colors[0])
                .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(CardButtonStyle())
        .matchedTransitionSource(id: Route.training(kind), in: zoom)
        .id("training-\(kind.rawValue)")
    }

    private func gridMetrics(_ snapshot: DashboardSnapshot) -> [MetricKind] {
        [.bodyBattery, .hrv, .steps, .stress].filter { snapshot.reading($0) != nil }
    }

    private func moreMetrics(_ snapshot: DashboardSnapshot) -> [MetricKind]? {
        [.heartRate, .intensityMinutes, .vo2Max, .calories].filter { snapshot.reading($0) != nil }
    }
}

// MARK: - Header & banners

struct DashboardHeader: View {
    var snapshot: DashboardSnapshot
    var isRefreshing: Bool
    var onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalDay.date(from: snapshot.calendarDate) ?? .now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(Self.greeting)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Image(systemName: "applewatch")
                    if let device = snapshot.source.deviceName {
                        Text(device)
                    }
                    if let sync = snapshot.source.lastSyncAt {
                        Text("· synchro \(sync.relativeToClock)")
                    }
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .bold))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    .frame(width: 22, height: 22)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Actualiser"))
        }
        .padding(.top, 8)
    }

    static var greeting: String {
        switch Calendar.current.component(.hour, from: DemoData.clock) {
        case 5..<12: String(localized: "Bonjour")
        case 12..<18: String(localized: "Bon après-midi")
        default: String(localized: "Bonsoir")
        }
    }
}

struct Banner {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?

    init?(snapshot: DashboardSnapshot, error: APIError?) {
        if snapshot.needsReauth || error == .providerReauthRequired {
            symbol = "exclamationmark.arrow.triangle.2.circlepath"
            title = String(localized: "Session Garmin expirée")
            message = String(localized: "Les données affichées datent de la dernière synchronisation.")
            actionTitle = String(localized: "Reconnecter")
        } else if let error {
            symbol = "icloud.slash"
            title = String(localized: "Données en cache")
            message = error.errorDescription ?? ""
            actionTitle = nil
        } else if snapshot.stale {
            symbol = "clock.badge.exclamationmark"
            title = String(localized: "Garmin ne répond pas")
            message = String(localized: "Affichage des dernières données reçues.")
            actionTitle = nil
        } else {
            return nil
        }
    }
}

struct StatusBanner: View {
    var banner: Banner
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline.weight(.semibold))
                Text(banner.message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let title = banner.actionTitle {
                Button(title, action: action)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .cardSurface(tint: .orange, cornerRadius: 20)
    }
}

// MARK: - Day rings

/// Signature card: Body Battery, sleep and readiness as concentric rings.
struct DayRingsCard: View {
    var snapshot: DashboardSnapshot

    private var readings: [MetricReading] {
        [MetricKind.bodyBattery, .sleep, .readiness].compactMap { snapshot.reading($0) }
    }

    var body: some View {
        HStack(spacing: 20) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let line = side * 0.095
                ZStack {
                    ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                        RingGauge(progress: reading.progress ?? 0, colors: reading.kind.colors, lineWidth: line)
                            .padding(CGFloat(index) * (line + side * 0.035))
                    }
                }
                .frame(width: side, height: side)
            }
            .frame(width: 136, height: 136)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(readings, id: \.kind) { reading in
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(reading.kind.gradient)
                            .frame(width: 4, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(reading.kind.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(reading.value)
                                    .font(.metric(22))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                if let label = reading.label {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(reading.kind.gradient)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .cardSurface(tint: MetricKind.readiness.tint)
    }
}

/// Subtle press feedback for tappable cards.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .foregroundStyle(.primary)
    }
}

#Preview {
    let model = AppModel()
    model.startDemo()
    return DashboardView().environment(model)
}

extension Date {
    /// "il y a 7 min", relative to DemoData.clock: the real time, except in DEBUG
    /// screenshots taken with -demoHour.
    var relativeToClock: String {
        DemoData.clock.formatted(Date.AnchoredRelativeFormatStyle(anchor: self, presentation: .named, unitsStyle: .abbreviated))
    }
}
