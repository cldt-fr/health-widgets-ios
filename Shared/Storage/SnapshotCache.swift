import Foundation

/// Last good snapshot on disk, in the App Group container: widgets render it instantly
/// and fall back to it when the network is slow or the server unreachable.
nonisolated struct SnapshotCache: Sendable {
    var fileURL: URL = AppGroup.containerURL.appending(path: "snapshot.json")

    func load() -> DashboardSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONCoding.decoder.decode(DashboardSnapshot.self, from: data)
    }

    func save(_ snapshot: DashboardSnapshot) {
        guard let data = try? JSONCoding.encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

nonisolated enum JSONCoding {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
