import Foundation

/// Garmin returns enum-like keys ("BALANCED", "READY_FOR_ACTION", "PRODUCTIVE_6"...).
/// This turns them into short French labels, and humanizes keys we don't know yet.
nonisolated enum GarminTerms {
    static func label(_ key: String?) -> String? {
        guard let raw = key?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let normalized = raw.lowercased().replacing(/_\d+$/, with: "")
        if let known = labels[normalized] { return known }
        return normalized.replacingOccurrences(of: "_", with: " ").capitalized(with: .current)
    }

    private static let labels: [String: String] = [
        // Qualifiers (sleep, stress, factors)
        "excellent": String(localized: "Excellent"),
        "very_good": String(localized: "Très bon"),
        "good": String(localized: "Bon"),
        "fair": String(localized: "Passable"),
        "moderate": String(localized: "Modéré"),
        "poor": String(localized: "Faible"),
        "very_poor": String(localized: "Très faible"),
        "calm": String(localized: "Calme"),
        "balanced": String(localized: "Équilibré"),
        "stressful": String(localized: "Stressant"),
        "very_stressful": String(localized: "Très stressant"),
        // HRV status
        "unbalanced": String(localized: "Déséquilibrée"),
        "low": String(localized: "Basse"),
        "hrv_balanced": String(localized: "VFC dans votre plage habituelle"),
        "hrv_unbalanced": String(localized: "VFC hors de votre plage habituelle"),
        "hrv_low": String(localized: "VFC basse"),
        "hrv_poor": String(localized: "VFC très basse"),
        // Training readiness levels & feedback
        "prime": String(localized: "Optimale"),
        "high": String(localized: "Élevée"),
        "ready_for_action": String(localized: "Prêt à l'action"),
        "primed_and_ready": String(localized: "Au top, prêt à performer"),
        "well_rested": String(localized: "Bien reposé"),
        "well_recovered": String(localized: "Bien récupéré"),
        "recovering": String(localized: "En récupération"),
        "low_readiness": String(localized: "Récupération prioritaire"),
        // Training status
        "productive": String(localized: "Productif"),
        "maintaining": String(localized: "Maintien"),
        "recovery": String(localized: "Récupération"),
        "unproductive": String(localized: "Improductif"),
        "detraining": String(localized: "Désentraînement"),
        "overreaching": String(localized: "Surcharge"),
        "peaking": String(localized: "Pic de forme"),
        "strained": String(localized: "Tendu"),
        "no_status": String(localized: "Pas de statut"),
        "optimal": String(localized: "Optimale"),
        // Readiness factors
        "sleep": String(localized: "Sommeil"),
        "recovery_time": String(localized: "Temps de récupération"),
        "hrv": String(localized: "VFC"),
        "acute_load": String(localized: "Charge aiguë"),
        "sleep_history": String(localized: "Historique de sommeil"),
        "stress_history": String(localized: "Historique de stress"),
        // Activity training effects
        "recovery_effect": String(localized: "Récupération"),
        "aerobic_base": String(localized: "Base aérobie"),
        "tempo": String(localized: "Tempo"),
        "lactate_threshold": String(localized: "Seuil lactique"),
        "vo2max": String(localized: "VO₂ max"),
        "anaerobic_capacity": String(localized: "Capacité anaérobie"),
        "sprint": String(localized: "Sprint"),
        // Sleep feedback
        "positive_long_and_deep": String(localized: "Nuit longue et profonde"),
        "positive_deep": String(localized: "Beaucoup de sommeil profond"),
        "positive_optimal_structure": String(localized: "Structure de sommeil optimale"),
        "negative_long_but_light": String(localized: "Long mais léger"),
        "negative_short": String(localized: "Nuit trop courte"),
    ]

    /// SF Symbol for an activity type key ("running", "trail_running", "lap_swimming"...).
    static func activitySymbol(_ type: String) -> String {
        let type = type.lowercased()
        if type.contains("run") { return "figure.run" }
        if type.contains("cycl") || type.contains("bik") || type.contains("ride") { return "figure.outdoor.cycle" }
        if type.contains("swim") { return "figure.pool.swim" }
        if type.contains("strength") || type.contains("weight") { return "figure.strengthtraining.traditional" }
        if type.contains("hik") { return "figure.hiking" }
        if type.contains("walk") { return "figure.walk" }
        if type.contains("yoga") || type.contains("pilates") || type.contains("breath") { return "figure.yoga" }
        if type.contains("ski") || type.contains("snow") { return "figure.skiing.downhill" }
        if type.contains("row") { return "figure.rower" }
        if type.contains("tennis") || type.contains("padel") { return "figure.tennis" }
        if type.contains("climb") || type.contains("bouldering") { return "figure.climbing" }
        if type.contains("golf") { return "figure.golf" }
        if type.contains("elliptical") { return "figure.elliptical" }
        if type.contains("hiit") || type.contains("cardio") { return "figure.highintensity.intervaltraining" }
        return "figure.mixed.cardio"
    }

    static func activityName(_ type: String) -> String {
        let names: [String: String] = [
            "running": String(localized: "Course à pied"),
            "trail_running": String(localized: "Trail"),
            "treadmill_running": String(localized: "Tapis de course"),
            "cycling": String(localized: "Vélo"),
            "road_biking": String(localized: "Vélo de route"),
            "mountain_biking": String(localized: "VTT"),
            "indoor_cycling": String(localized: "Home trainer"),
            "lap_swimming": String(localized: "Natation"),
            "open_water_swimming": String(localized: "Eau libre"),
            "strength_training": String(localized: "Renforcement"),
            "walking": String(localized: "Marche"),
            "hiking": String(localized: "Randonnée"),
            "yoga": String(localized: "Yoga"),
        ]
        return names[type.lowercased()] ?? type.replacingOccurrences(of: "_", with: " ").capitalized(with: .current)
    }
}
