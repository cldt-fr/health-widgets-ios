import Foundation
import Observation
import WidgetKit

/// App-wide state: onboarding, today's snapshot, connections, deep links.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case onboarding, dashboard }
    enum Tab: Hashable { case today, widgets, settings }

    enum GarminStep: Equatable {
        case connected
        case needsCode(challengeID: String)
    }

    var phase: Phase
    var tab: Tab = .today
    var snapshot: DashboardSnapshot?
    var isRefreshing = false
    /// Last refresh problem (shown as a banner); the cached snapshot stays on screen.
    var refreshError: APIError?
    var connections: [ConnectionInfo] = []
    /// Set by deep links (widget taps) to open a metric's detail.
    var focusedMetric: MetricKind?
    var focusedTraining: TrainingKind?
    var showsLastActivity = false

    private let settings = SharedSettings()
    private let keychain = KeychainStore()
    private let cache = SnapshotCache()
    private var repository: SnapshotRepository { SnapshotRepository() }

    var isDemo: Bool { settings.isDemoMode }
    var serverURL: URL? { settings.serverURL }

    init() {
        let ready = settings.isOnboarded && (settings.isDemoMode || keychain.read() != nil)
        phase = ready ? .dashboard : .onboarding
        snapshot = ready ? SnapshotRepository().cached() : nil
        applyLaunchArguments()
    }

    // MARK: Onboarding

    func startDemo() {
        settings.isDemoMode = true
        settings.isOnboarded = true
        snapshot = DemoData.snapshot()
        refreshError = nil
        phase = .dashboard
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Checks the server and registers this install (once) to get a device token.
    func prepareServer(url: URL, signupCode: String?) async throws {
        let sameServer = settings.serverURL == url
        if sameServer, let token = keychain.read() {
            do {
                _ = try await APIClient(baseURL: url, token: token).me()
                return
            } catch APIError.invalidDeviceToken {
                keychain.delete()  // server was reset: register again below
            }
        }
        let response = try await APIClient(baseURL: url, token: nil)
            .registerDevice(name: Self.deviceName, signupCode: signupCode)
        guard keychain.save(response.token) else {
            throw APIError.server(status: 0, code: "keychain", message: String(localized: "Impossible d'enregistrer le jeton dans le trousseau."))
        }
        settings.serverURL = url
    }

    func connectGarmin(email: String, password: String, isChina: Bool) async throws -> GarminStep {
        let response = try await authorizedClient().connectGarmin(email: email, password: password, isChina: isChina)
        if response.needsMFA, let challenge = response.challengeId {
            return .needsCode(challengeID: challenge)
        }
        return .connected
    }

    func submitGarminCode(challengeID: String, code: String) async throws {
        _ = try await authorizedClient().submitGarminCode(challengeID: challengeID, code: code)
    }

    func finishOnboarding() {
        settings.isDemoMode = false
        settings.isOnboarded = true
        phase = .dashboard
        tab = .today
        Task { await refresh(force: true) }
    }

    // MARK: Data

    func refresh(force: Bool = false) async {
        guard phase == .dashboard, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await repository.load(refresh: force)
            snapshot = result.snapshot
            refreshError = result.error ?? (result.snapshot.needsReauth ? .providerReauthRequired : nil)
            WidgetCenter.shared.reloadAllTimelines()
        } catch let error as APIError {
            refreshError = error
        } catch {
            refreshError = .network(error.localizedDescription)
        }
    }

    func loadConnections() async {
        guard !isDemo, let client = repository.client else {
            connections = []
            return
        }
        connections = (try? await client.me().connections) ?? connections
    }

    func disconnect(_ provider: ProviderID) async {
        guard let client = repository.client else { return }
        try? await client.disconnect(provider)
        cache.clear()
        snapshot = nil
        await loadConnections()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Forget everything on this device (the server account stays unless deleted first).
    func signOut() {
        keychain.delete()
        cache.clear()
        settings.reset()
        snapshot = nil
        connections = []
        refreshError = nil
        phase = .onboarding
        WidgetCenter.shared.reloadAllTimelines()
    }

    func deleteServerAccount() async throws {
        if let client = repository.client {
            try await client.deleteAccount()
        }
        signOut()
    }

    // MARK: Deep links (widget taps)

    func handle(_ url: URL) {
        guard url.scheme == DeepLink.scheme, phase == .dashboard else { return }
        tab = .today
        switch url.host() {
        case "metric":
            focusedMetric = MetricKind(rawValue: url.lastPathComponent)
        case "training":
            focusedTraining = TrainingKind(rawValue: url.lastPathComponent)
        case "activity":
            showsLastActivity = true
        default:
            break
        }
    }

    // MARK: Helpers

    private func authorizedClient() throws -> APIClient {
        guard let url = settings.serverURL, let token = keychain.read() else {
            throw APIError.invalidDeviceToken
        }
        return APIClient(baseURL: url, token: token)
    }

    private static var deviceName: String {
        #if targetEnvironment(simulator)
        "Simulator"
        #else
        "iPhone"
        #endif
    }

    /// `-demo`, `-tab widgets|settings`, `-metric <kind>`: handy for screenshots and UI tests.
    private func applyLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo") { startDemo() }
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            tab = switch arguments[index + 1] {
            case "widgets": .widgets
            case "settings": .settings
            default: .today
            }
        }
        if let index = arguments.firstIndex(of: "-metric"), index + 1 < arguments.count {
            focusedMetric = MetricKind(rawValue: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "-training"), index + 1 < arguments.count {
            focusedTraining = TrainingKind(rawValue: arguments[index + 1])
        }
        if arguments.contains("-onboarding") { phase = .onboarding }
        // End-to-end check against a local server running with HW_ENABLE_DEMO_PROVIDER=true:
        // registers this install, connects the server-side demo provider, opens the dashboard.
        if let index = arguments.firstIndex(of: "-e2e-server"), index + 1 < arguments.count,
           let url = URL(string: arguments[index + 1]) {
            settings.isDemoMode = false
            Task {
                do {
                    try await prepareServer(url: url, signupCode: nil)
                    _ = try await authorizedClient().connectDemo()
                    finishOnboarding()
                } catch {
                    refreshError = error as? APIError
                    print("E2E setup failed: \(error)")
                }
            }
        }
        #endif
    }
}
