import SwiftUI
import WidgetKit

/// Every widget, rendered live with today's data, plus how to add them.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model

    private var entrySnapshot: DashboardSnapshot { model.snapshot ?? DemoData.snapshot() }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HowToCard()

                    GallerySection(title: "Petits widgets", subtitle: "Une métrique, en grand. Touchez longuement un widget pour choisir laquelle.") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(MetricKind.allCases.filter { entrySnapshot.reading($0) != nil }) { kind in
                                    WidgetPreviewFrame(family: .systemSmall, kind: kind) {
                                        MetricWidgetView(entry: entry(kind), family: .systemSmall)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .padding(.horizontal, -16)
                    }

                    GallerySection(title: "Widgets moyens", subtitle: "Détails, courbes et phases de sommeil.") {
                        VStack(spacing: 14) {
                            WidgetPreviewFrame(family: .systemMedium, kind: .readiness) {
                                OverviewWidgetView(entry: entry(.readiness), family: .systemMedium)
                            }
                            ForEach([MetricKind.sleep, .bodyBattery, .readiness, .steps], id: \.self) { kind in
                                if entrySnapshot.reading(kind) != nil {
                                    WidgetPreviewFrame(family: .systemMedium, kind: kind) {
                                        MetricWidgetView(entry: entry(kind), family: .systemMedium)
                                    }
                                }
                            }
                            if entrySnapshot.lastActivity != nil {
                                WidgetPreviewFrame(family: .systemMedium, kind: .calories) {
                                    ActivityWidgetView(entry: entry(.intensityMinutes), family: .systemMedium)
                                }
                            }
                        }
                    }
                    .id("medium")

                    GallerySection(title: "Grand widget", subtitle: "Votre journée complète, avec bouton d'actualisation.") {
                        WidgetPreviewFrame(family: .systemLarge, kind: .readiness) {
                            OverviewWidgetView(entry: entry(.readiness), family: .systemLarge)
                        }
                    }
                    .id("large")

                    GallerySection(title: "Écran verrouillé", subtitle: "Discrets, lisibles d'un coup d'œil, et teintés selon votre fond d'écran.") {
                        LockScreenShowcase(snapshot: entrySnapshot)
                    }
                    .id("lock")
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .debugScrollTarget(proxy)
            }
            .background(AuroraBackground())
            .navigationTitle("Widgets")
        }
    }

    private func entry(_ kind: MetricKind) -> HealthEntry {
        HealthEntry(date: .now, snapshot: entrySnapshot, metric: kind)
    }
}

struct HowToCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ajouter un widget", systemImage: "plus.square.on.square")
                .font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.metric(13))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(MetricKind.bodyBattery.gradient))
                        .foregroundStyle(.white)
                    Text(step)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: MetricKind.bodyBattery.tint)
    }

    private var steps: [String] {
        [
            String(localized: "Maintenez le doigt sur l'écran d'accueil (ou l'écran verrouillé) puis touchez « Modifier »."),
            String(localized: "Touchez « Ajouter des widgets » et cherchez Health Widgets."),
            String(localized: "Pour le widget « Métrique », touchez-le longuement puis « Modifier le widget » pour choisir la donnée."),
        ]
    }
}

struct GallerySection<Content: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Renders a widget view at its real size, on the same backdrop as on the Home Screen.
struct WidgetPreviewFrame<Content: View>: View {
    var family: WidgetFamily
    var kind: MetricKind?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(width: width, height: height)
            .frame(maxWidth: maxWidth)
            .background {
                if !isAccessory { WidgetBackdrop(kind: kind) }
            }
            .clipShape(RoundedRectangle(cornerRadius: isAccessory ? 14 : 24, style: .continuous))
            .shadow(color: .black.opacity(isAccessory ? 0 : 0.28), radius: 16, y: 8)
    }

    private var isAccessory: Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    private var padding: CGFloat { isAccessory ? 0 : 16 }

    private var width: CGFloat? {
        switch family {
        case .systemSmall: 170
        case .accessoryCircular: 76
        case .accessoryRectangular: 172
        default: nil
        }
    }

    private var maxWidth: CGFloat? {
        switch family {
        case .systemMedium, .systemLarge: 364
        default: nil
        }
    }

    private var height: CGFloat {
        switch family {
        case .systemSmall, .systemMedium: 170
        case .systemLarge: 382
        case .accessoryCircular, .accessoryRectangular: 76
        default: 26
        }
    }
}

struct LockScreenShowcase: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 18) {
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 14) {
                ForEach([MetricKind.bodyBattery, .readiness, .steps, .sleep], id: \.self) { kind in
                    WidgetPreviewFrame(family: .accessoryCircular) {
                        MetricWidgetView(entry: HealthEntry(date: .now, snapshot: snapshot, metric: kind), family: .accessoryCircular)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach([MetricKind.hrv, .stress], id: \.self) { kind in
                    WidgetPreviewFrame(family: .accessoryRectangular) {
                        MetricWidgetView(entry: HealthEntry(date: .now, snapshot: snapshot, metric: kind), family: .accessoryRectangular)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: 0x1B2A6B), Color(hex: 0x4A1E6E), Color(hex: 0x0B0D18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

#Preview {
    let model = AppModel()
    model.startDemo()
    return WidgetGalleryView().environment(model)
}
