import SwiftUI
import WidgetKit

/// Gradient ring with a glowing tip. Falls back to a flat, accentable stroke when the
/// system renders widgets tinted (accented) or on the Lock Screen (vibrant).
struct RingGauge: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 10
    var trackOpacity: Double = 0.16

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fill: Double { min(max(progress, 0), 1) }
    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2
            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(isFullColor ? colors[0].opacity(trackOpacity) : Color.primary.opacity(0.18), lineWidth: lineWidth)

                if fill > 0 {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: fill)
                        .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: isFullColor ? colors[1].opacity(0.45) : .clear, radius: lineWidth * 0.7)
                        .widgetAccentable()

                    if isFullColor && fill > 0.04 {
                        Circle()
                            .fill(colors[1])
                            .frame(width: lineWidth * 0.62, height: lineWidth * 0.62)
                            .shadow(color: .white.opacity(0.7), radius: lineWidth * 0.35)
                            .offset(y: -radius)
                            .rotationEffect(.degrees(360 * fill))
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fill * 100).rounded())) %"))
    }

    private var stroke: AnyShapeStyle {
        guard isFullColor else { return AnyShapeStyle(Color.primary) }
        return AnyShapeStyle(
            AngularGradient(
                gradient: Gradient(colors: colors),
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(max(360 * fill, 1))
            )
        )
    }
}

/// A ring with a value in the middle: the signature element of the cards and widgets.
struct RingValue: View {
    var reading: MetricReading
    var lineWidth: CGFloat = 10
    var valueSize: CGFloat = 26
    var showsIcon = true

    var body: some View {
        ZStack {
            RingGauge(progress: reading.progress ?? 0, colors: reading.kind.colors, lineWidth: lineWidth)
            VStack(spacing: 0) {
                if showsIcon {
                    Image(systemName: reading.kind.symbol)
                        .font(.system(size: valueSize * 0.42, weight: .semibold))
                        .foregroundStyle(reading.kind.gradient)
                        .widgetAccentable()
                }
                Text(reading.value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if let unit = reading.unit, valueSize > 20 {
                    Text(unit)
                        .font(.system(size: valueSize * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(lineWidth * 1.4)
            // The ring is drawn in the largest centered square: size the text against that
            // square, not the whole frame, so "10 811" shrinks instead of crossing the ring
            // when the frame is wider than tall (small widget).
            .aspectRatio(1, contentMode: .fit)
        }
    }
}
