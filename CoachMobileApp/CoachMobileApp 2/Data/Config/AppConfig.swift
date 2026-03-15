import Foundation

enum AppConfig {
    /// Default for iOS Simulator with local backend proxy.
    /// On a physical iPhone launched from Xcode, set scheme environment variable
    /// VOICE_API_BASE_URL to your Mac LAN URL (e.g. http://192.168.1.23:8787).
    /// You can also override via UserDefaults key "voiceProcessingBaseURL".
    private static let defaultBaseURL = "http://127.0.0.1:8787"

    static var voiceProcessingBaseURL: URL {
        if let envValue = ProcessInfo.processInfo.environment["VOICE_API_BASE_URL"],
           let url = URL(string: envValue),
           !envValue.isEmpty {
            return url
        }

        if let configured = UserDefaults.standard.string(forKey: "voiceProcessingBaseURL"),
           let url = URL(string: configured),
           !configured.isEmpty {
            return url
        }

        return URL(string: defaultBaseURL)!
    }
}
