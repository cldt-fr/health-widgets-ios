import Foundation

nonisolated enum APIError: LocalizedError, Sendable, Equatable {
    /// The device token is unknown to the server (revoked, or the server was reset).
    case invalidDeviceToken
    /// The provider session expired: the user must sign in to Garmin again.
    case providerReauthRequired
    case noProviderConnected
    case rateLimited(retryAfter: Int?)
    case server(status: Int, code: String, message: String)
    case offline
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidDeviceToken:
            String(localized: "Cet appareil n'est plus reconnu par le serveur.")
        case .providerReauthRequired:
            String(localized: "La session Garmin a expiré. Reconnectez-vous.")
        case .noProviderConnected:
            String(localized: "Aucune montre n'est connectée.")
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                String(localized: "Garmin limite les requêtes. Réessayez dans \(max(1, retryAfter / 60)) min.")
            } else {
                String(localized: "Garmin limite les requêtes. Réessayez dans quelques minutes.")
            }
        case .server(_, _, let message):
            message
        case .offline:
            String(localized: "Pas de connexion Internet.")
        case .network(let message):
            String(localized: "Serveur injoignable (\(message)).")
        case .decoding:
            String(localized: "Réponse du serveur illisible. L'app est-elle à jour ?")
        }
    }

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }
}

/// Typed client for the Health Widgets sync server (see `backend/README.md`).
nonisolated struct APIClient: Sendable {
    var baseURL: URL
    var token: String?
    var session: URLSession = .shared

    // MARK: Devices & account

    func registerDevice(name: String?, signupCode: String?) async throws -> RegisterDeviceResponse {
        try await send(
            "POST", "v1/devices",
            body: RegisterDeviceRequest(name: name, signupCode: signupCode?.nilIfBlank),
            authenticated: false
        )
    }

    func me() async throws -> MeResponse {
        try await send("GET", "v1/me")
    }

    func deleteAccount() async throws {
        let _: Empty = try await send("DELETE", "v1/me")
    }

    // MARK: Providers

    func connectGarmin(email: String, password: String, isChina: Bool) async throws -> ConnectResponse {
        // Garmin's SSO can take a while (several strategies, Cloudflare checks).
        try await send(
            "POST", "v1/connections/garmin",
            body: GarminConnectRequest(email: email, password: password, isCn: isChina),
            timeout: 120
        )
    }

    func submitGarminCode(challengeID: String, code: String) async throws -> ConnectResponse {
        try await send(
            "POST", "v1/connections/garmin/mfa",
            body: MfaRequest(challengeId: challengeID, code: code),
            timeout: 120
        )
    }

    func connectDemo() async throws -> ConnectResponse {
        try await send("POST", "v1/connections/demo")
    }

    func disconnect(_ provider: ProviderID) async throws {
        let _: Empty = try await send("DELETE", "v1/connections/\(provider.rawValue)")
    }

    // MARK: Data

    func snapshot(day: String, refresh: Bool = false, timeout: TimeInterval = 45) async throws -> DashboardSnapshot {
        var query = [URLQueryItem(name: "date", value: day)]
        if refresh { query.append(URLQueryItem(name: "refresh", value: "true")) }
        return try await send("GET", "v1/snapshot", query: query, timeout: timeout)
    }

    // MARK: Transport

    private struct Empty: Decodable {}
    private struct NoBody: Encodable {}

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = 30,
        authenticated: Bool = true
    ) async throws -> Response {
        try await send(method, path, query: query, body: NoBody?.none, timeout: timeout, authenticated: authenticated)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Body?,
        timeout: TimeInterval = 30,
        authenticated: Bool = true
    ) async throws -> Response {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.offline
            default:
                throw APIError.network(error.localizedDescription)
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, data: data, response: response)
        }
        if Response.self == Empty.self || data.isEmpty {
            if let empty = Empty() as? Response { return empty }
        }
        do {
            return try JSONCoding.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private static func error(status: Int, data: Data, response: URLResponse) -> APIError {
        let envelope = try? JSONCoding.decoder.decode(APIErrorEnvelope.self, from: data)
        let code = envelope?.error.code ?? "http_\(status)"
        let message = envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: status)
        let retryAfter = envelope?.error.retryAfterSeconds
            ?? (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        switch code {
        case "invalid_token": return .invalidDeviceToken
        case "provider_reauth_required": return .providerReauthRequired
        case "no_provider_connected": return .noProviderConnected
        case "provider_rate_limited", "too_many_login_attempts": return .rateLimited(retryAfter: retryAfter)
        default: return .server(status: status, code: code, message: message)
        }
    }
}

nonisolated extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
