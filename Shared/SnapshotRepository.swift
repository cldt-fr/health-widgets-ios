import Foundation

/// The single way the app and the widgets get data: server (or on-device demo), with the
/// App Group cache as fallback so a widget always has something to show.
nonisolated struct SnapshotRepository: Sendable {
    var settings = SharedSettings()
    var keychain = KeychainStore()
    var cache = SnapshotCache()

    enum Source: Sendable { case network, cache }

    struct Result: Sendable {
        var snapshot: DashboardSnapshot
        var source: Source
        /// Set when fresh data could not be fetched and the cached snapshot was used.
        var error: APIError?
    }

    var isConfigured: Bool {
        settings.isDemoMode || (settings.serverURL != nil && keychain.read() != nil)
    }

    var client: APIClient? {
        guard let url = settings.serverURL else { return nil }
        return APIClient(baseURL: url, token: keychain.read())
    }

    func cached() -> DashboardSnapshot? {
        if settings.isDemoMode { return DemoData.snapshot() }
        return cache.load()
    }

    /// Fetches today's snapshot. Falls back to the cache (and reports why) on failure.
    /// Runs off the main actor: network, JSON decoding and the cache write.
    @concurrent
    func load(refresh: Bool = false, timeout: TimeInterval = 45) async throws -> Result {
        if settings.isDemoMode {
            return Result(snapshot: DemoData.snapshot(), source: .network)
        }
        guard let client, client.token != nil else {
            throw APIError.invalidDeviceToken
        }
        do {
            let snapshot = try await client.snapshot(day: LocalDay.string(), refresh: refresh, timeout: timeout)
            cache.save(snapshot)
            return Result(snapshot: snapshot, source: .network)
        } catch let error as APIError {
            if let cached = cache.load(), Self.canFallBack(on: error) {
                return Result(snapshot: cached, source: .cache, error: error)
            }
            throw error
        }
    }

    private static func canFallBack(on error: APIError) -> Bool {
        switch error {
        case .invalidDeviceToken, .noProviderConnected: false
        default: true
        }
    }
}
