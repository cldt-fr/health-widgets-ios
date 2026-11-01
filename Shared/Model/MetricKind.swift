import AppIntents
import Foundation

/// The metrics a card or a widget can feature.
nonisolated enum MetricKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case bodyBattery
    case sleep
    case readiness
    case hrv
    case steps
    case stress
    case heartRate
    case intensityMinutes
    case calories
    case vo2Max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyBattery: String(localized: "Body Battery")
        case .sleep: String(localized: "Sommeil")
        case .readiness: String(localized: "Disposition")
        case .hrv: String(localized: "VFC")
        case .steps: String(localized: "Pas")
        case .stress: String(localized: "Stress")
        case .heartRate: String(localized: "Fréquence cardiaque")
        case .intensityMinutes: String(localized: "Minutes intensives")
        case .calories: String(localized: "Calories")
        case .vo2Max: String(localized: "VO₂ max")
        }
    }

    /// Short label for tight layouts (lock screen, small tiles).
    var shortTitle: String {
        switch self {
        case .bodyBattery: String(localized: "Énergie")
        case .readiness: String(localized: "Forme")
        case .heartRate: String(localized: "FC repos")
        case .intensityMinutes: String(localized: "Intensité")
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .bodyBattery: "bolt.heart.fill"
        case .sleep: "moon.stars.fill"
        case .readiness: "gauge.with.dots.needle.67percent"
        case .hrv: "waveform.path.ecg"
        case .steps: "figure.walk"
        case .stress: "brain.head.profile"
        case .heartRate: "heart.fill"
        case .intensityMinutes: "flame.fill"
        case .calories: "bolt.fill"
        case .vo2Max: "lungs.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .bodyBattery: String(localized: "Votre réserve d'énergie, de 0 à 100")
        case .sleep: String(localized: "Score, durée et phases de la nuit")
        case .readiness: String(localized: "Prêt pour l'entraînement ?")
        case .hrv: String(localized: "Variabilité de la fréquence cardiaque")
        case .steps: String(localized: "Progression vers l'objectif du jour")
        case .stress: String(localized: "Niveau de stress de la journée")
        case .heartRate: String(localized: "FC au repos et courbe du jour")
        case .intensityMinutes: String(localized: "Objectif hebdomadaire de l'OMS")
        case .calories: String(localized: "Dépense active et totale")
        case .vo2Max: String(localized: "Capacité aérobie et statut d'entraînement")
        }
    }
}

// App Intents metadata is extracted at build time: these must stay literals.
extension MetricKind: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Métrique"

    static let caseDisplayRepresentations: [MetricKind: DisplayRepresentation] = [
        .bodyBattery: DisplayRepresentation(title: "Body Battery", subtitle: "Réserve d'énergie, de 0 à 100", image: .init(systemName: "bolt.heart.fill")),
        .sleep: DisplayRepresentation(title: "Sommeil", subtitle: "Score, durée et phases", image: .init(systemName: "moon.stars.fill")),
        .readiness: DisplayRepresentation(title: "Disposition à l'entraînement", subtitle: "Prêt pour l'effort ?", image: .init(systemName: "gauge.with.dots.needle.67percent")),
        .hrv: DisplayRepresentation(title: "VFC", subtitle: "Variabilité de la fréquence cardiaque", image: .init(systemName: "waveform.path.ecg")),
        .steps: DisplayRepresentation(title: "Pas", subtitle: "Objectif du jour", image: .init(systemName: "figure.walk")),
        .stress: DisplayRepresentation(title: "Stress", subtitle: "Niveau de la journée", image: .init(systemName: "brain.head.profile")),
        .heartRate: DisplayRepresentation(title: "Fréquence cardiaque", subtitle: "FC au repos et courbe du jour", image: .init(systemName: "heart.fill")),
        .intensityMinutes: DisplayRepresentation(title: "Minutes intensives", subtitle: "Objectif hebdomadaire", image: .init(systemName: "flame.fill")),
        .calories: DisplayRepresentation(title: "Calories", subtitle: "Dépense active et totale", image: .init(systemName: "bolt.fill")),
        .vo2Max: DisplayRepresentation(title: "VO₂ max", subtitle: "Capacité aérobie", image: .init(systemName: "lungs.fill")),
    ]
}
