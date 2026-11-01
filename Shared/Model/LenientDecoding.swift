import Foundation

nonisolated extension KeyedDecodingContainer {
    /// Missing or `null` arrays decode as empty instead of failing, so an older app keeps
    /// working when the server adds or drops optional sections. Synthesized `Codable`
    /// conformances in this module pick this overload for every `[T]` property.
    func decode<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent(type, forKey: key) ?? []
    }
}
