import SwiftUI
import WidgetKit

extension Font {
    /// Big rounded numerals used for every metric value.
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Uppercase caption with the metric's gradient glyph.
struct MetricTitle: View {
    var kind: MetricKind
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

/// "62 bpm" with the unit sitting on the baseline, smaller and dimmer.
struct ValueLabel: View {
    var value: String
    var unit: String?
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.metric(size))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.metric(size * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Glyph on a soft gradient tile.
struct MetricBadge: View {
    var kind: MetricKind
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(kind.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: kind.tint.opacity(0.45), radius: size * 0.25, y: size * 0.1)
    }
}

/// Frosted card used across the app: translucent fill, hairline gradient border and a
/// glow tinted by the metric.
struct CardSurface: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            ZStack {
                shape.fill(dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82))
                if let tint {
                    shape.fill(
                        RadialGradient(
                            colors: [tint.opacity(dark ? 0.26 : 0.13), .clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 240
                        )
                    )
                }
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(dark ? 0.16 : 0.95), Color.white.opacity(dark ? 0.02 : 0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(dark ? 0.35 : 0.07), radius: 20, y: 10)
        }
    }
}

extension View {
    func cardSurface(tint: Color? = nil, cornerRadius: CGFloat = 26) -> some View {
        modifier(CardSurface(tint: tint, cornerRadius: cornerRadius))
    }
}

/// Aurora-like mesh behind the app.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: colorScheme == .dark
                ? [
                    Color(hex: 0x07080D), Color(hex: 0x0E1330), Color(hex: 0x07080D),
                    Color(hex: 0x131B45), Color(hex: 0x090A12), Color(hex: 0x24113F),
                    Color(hex: 0x07080D), Color(hex: 0x0A2A2E), Color(hex: 0x07080D),
                ]
                : [
                    Color(hex: 0xF5F6FB), Color(hex: 0xE5ECFF), Color(hex: 0xF5F6FB),
                    Color(hex: 0xE9F2FF), Color(hex: 0xF8F8FC), Color(hex: 0xF1E8FF),
                    Color(hex: 0xF5F6FB), Color(hex: 0xE3FAF4), Color(hex: 0xF5F6FB),
                ]
        )
        .ignoresSafeArea()
    }
}

/// Background shared by every widget (and the in-app widget gallery).
struct WidgetBackdrop: View {
    var colors: [Color]?

    init(kind: MetricKind?) { colors = kind?.colors }
    init(training: TrainingKind) { colors = training.colors }
    init(colors: [Color]?) { self.colors = colors }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: dark ? [Color(hex: 0x141724), Color(hex: 0x08090E)] : [.white, Color(hex: 0xF0F2F8)],
                startPoint: .top,
                endPoint: .bottom
            )
            if let colors {
                RadialGradient(
                    colors: [colors[0].opacity(dark ? 0.34 : 0.17), .clear],
                    center: .topTrailing,
                    startRadius: 2,
                    endRadius: 200
                )
                RadialGradient(
                    colors: [colors[1].opacity(dark ? 0.16 : 0.09), .clear],
                    center: .bottomLeading,
                    startRadius: 2,
                    endRadius: 170
                )
            }
        }
    }
}
