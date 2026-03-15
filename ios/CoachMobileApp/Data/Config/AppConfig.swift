import Foundation

enum AppConfig {
    private static let defaultBaseURL = "https://coach-backend-proxy.onrender.com"

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
