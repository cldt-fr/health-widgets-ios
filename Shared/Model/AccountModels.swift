import Foundation

nonisolated enum ProviderID: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case garmin, polar, coros, suunto, wahoo, demo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .garmin: "Garmin"
        case .polar: "Polar"
        case .coros: "COROS"
        case .suunto: "Suunto"
        case .wahoo: "Wahoo"
        case .demo: String(localized: "Démo")
        }
    }

    /// Providers the server can connect today. The others are on the roadmap.
    var isAvailable: Bool { self == .garmin || self == .demo }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProviderID(rawValue: raw) ?? .demo
    }
}

nonisolated struct RegisterDeviceRequest: Encodable, Sendable {
    var name: String?
    var signupCode: String?
}

nonisolated struct RegisterDeviceResponse: Decodable, Sendable {
    var token: String
    var userId: String
}

nonisolated struct ConnectionInfo: Codable, Sendable, Hashable, Identifiable {
    var provider: ProviderID
    var status: String
    var displayName: String?
    var fullName: String?
    var connectedAt: Date
    var lastSuccessAt: Date?
    var lastError: String?

    var id: ProviderID { provider }
    var needsReauth: Bool { status == "reauth_required" }
}

nonisolated struct MeResponse: Decodable, Sendable {
    var userId: String
    var connections: [ConnectionInfo] = []
}

nonisolated struct GarminConnectRequest: Encodable, Sendable {
    var email: String
    var password: String
    var isCn: Bool
}

nonisolated struct MfaRequest: Encodable, Sendable {
    var challengeId: String
    var code: String
}

nonisolated struct ConnectResponse: Decodable, Sendable {
    var status: String
    var challengeId: String?
    var connection: ConnectionInfo?

    var needsMFA: Bool { status == "mfa_required" }
}

nonisolated struct APIErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        var code: String
        var message: String
        var retryAfterSeconds: Int?
    }

    var error: Body
}
