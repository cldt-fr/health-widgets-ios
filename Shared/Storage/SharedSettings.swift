import Foundation

/// Non-secret preferences shared by the app and the widgets.
nonisolated struct SharedSettings: Sendable {
    private enum Key {
        static let serverURL = "serverURL"
        static let demoMode = "demoMode"
        static let onboarded = "onboarded"
    }

    /// Server pre-filled during setup: `HW_DEFAULT_SERVER_URL` from Config/Local.xcconfig if
    /// set; otherwise, in the Simulator, the Mac running the server (`docker compose up`).
    static let defaultServerURL: URL? = {
        if let raw = Bundle.main.buildSetting("HWDefaultServerURL"), let url = URL(string: raw), url.host() != nil {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:8000")
        #else
        return nil
        #endif
    }()

    var serverURL: URL? {
        get { AppGroup.defaults.string(forKey: Key.serverURL).flatMap(URL.init(string:)) }
        nonmutating set { AppGroup.defaults.set(newValue?.absoluteString, forKey: Key.serverURL) }
    }

    /// Offline demo: synthetic data generated on device, no server involved.
    var isDemoMode: Bool {
        get { AppGroup.defaults.bool(forKey: Key.demoMode) }
        nonmutating set { AppGroup.defaults.set(newValue, forKey: Key.demoMode) }
    }

    var isOnboarded: Bool {
        get { AppGroup.defaults.bool(forKey: Key.onboarded) }
        nonmutating set { AppGroup.defaults.set(newValue, forKey: Key.onboarded) }
    }

    func reset() {
        for key in [Key.serverURL, Key.demoMode, Key.onboarded] {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }
}
