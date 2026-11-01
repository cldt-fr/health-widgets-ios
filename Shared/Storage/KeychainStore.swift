import Foundation
import Security

/// The device token, in a keychain item shared with the widget extension through the
/// App Group access group. It stays readable after the first unlock so widgets can
/// refresh while the phone is locked.
nonisolated struct KeychainStore: Sendable {
    var service = "HealthWidgets.deviceToken"
    var accessGroup: String? = AppGroup.identifier

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement, accessGroup != nil {
            return Self.withoutGroup(self).read()
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status == errSecMissingEntitlement, accessGroup != nil {
            // Unsigned Simulator builds have no keychain-sharing entitlement.
            return Self.withoutGroup(self).save(token)
        }
        return status == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        if accessGroup != nil {
            SecItemDelete(Self.withoutGroup(self).baseQuery as CFDictionary)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device",
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func withoutGroup(_ store: KeychainStore) -> KeychainStore {
        var copy = store
        copy.accessGroup = nil
        return copy
    }
}
