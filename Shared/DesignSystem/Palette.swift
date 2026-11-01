import SwiftUI

nonisolated extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Each metric owns a two-stop gradient: it identifies the metric at a glance across
/// the dashboard, the widgets and the charts.
nonisolated extension MetricKind {
    var colors: [Color] {
        switch self {
        case .bodyBattery: [Color(hex: 0x2F7BFF), Color(hex: 0x3FE3FF)]
        case .sleep: [Color(hex: 0x6C5CFF), Color(hex: 0xC56BFF)]
        case .readiness: [Color(hex: 0x14D68C), Color(hex: 0xC4F53D)]
        case .hrv: [Color(hex: 0x00BFB3), Color(hex: 0x7DF7D4)]
        case .steps: [Color(hex: 0xFF7A1A), Color(hex: 0xFFCB47)]
        case .stress: [Color(hex: 0xFFAE3D), Color(hex: 0xFF4D6D)]
        case .heartRate: [Color(hex: 0xFF2E63), Color(hex: 0xFF8BA0)]
        case .intensityMinutes: [Color(hex: 0xFFD23F), Color(hex: 0xFF7B2E)]
        case .calories: [Color(hex: 0xFF5A36), Color(hex: 0xFFA14D)]
        case .vo2Max: [Color(hex: 0x7B61FF), Color(hex: 0x3D9BFF)]
        }
    }

    var tint: Color { colors[0] }
    var accent: Color { colors[1] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

nonisolated enum Palette {
    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .deep: Color(hex: 0x4B3BFF)
        case .light: Color(hex: 0x6FA8FF)
        case .rem: Color(hex: 0xC56BFF)
        case .awake: Color(hex: 0xFF8BA0)
        }
    }

    static func name(for stage: SleepStage) -> String {
        switch stage {
        case .deep: String(localized: "Profond")
        case .light: String(localized: "Léger")
        case .rem: String(localized: "Paradoxal")
        case .awake: String(localized: "Éveillé")
        }
    }

    /// Deep "night sky" used behind the app and the widgets in dark mode.
    static let night = Color(hex: 0x07080D)
    static let nightRaised = Color(hex: 0x11131C)
    static let daylight = Color(hex: 0xF4F5FA)
}
