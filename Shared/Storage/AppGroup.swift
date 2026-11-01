import Foundation

/// Everything the app and the widget extension share lives in this App Group:
/// settings, the cached snapshot and (as keychain access group) the device token.
nonisolated enum AppGroup {
    /// `HW_APP_GROUP` from Config/*.xcconfig, injected into both Info.plist files.
    static let identifier: String = Bundle.main.buildSetting("HWAppGroup") ?? "group.com.example.healthwidgets"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Only happens when the entitlement is missing (e.g. unsigned builds): fall back to
        // the process' own caches so the app keeps working, without widget sharing.
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

nonisolated extension Bundle {
    /// A value injected from an xcconfig build setting into Info.plist, or nil when the
    /// setting is empty (or was not expanded).
    func buildSetting(_ key: String) -> String? {
        guard let value = (object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty, !value.contains("$(")
        else { return nil }
        return value
    }
}
