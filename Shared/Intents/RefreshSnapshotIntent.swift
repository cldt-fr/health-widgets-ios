import AppIntents
import WidgetKit

/// Interactive "refresh" button in the large widget (also usable from Shortcuts/Siri).
struct RefreshSnapshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Actualiser les données santé"
    static let description = IntentDescription("Récupère les dernières données de votre montre.")

    func perform() async throws -> some IntentResult {
        _ = try? await SnapshotRepository().load(refresh: true, timeout: 20)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
