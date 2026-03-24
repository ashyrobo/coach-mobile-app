import Foundation

enum TranscriptionMethod: String, CaseIterable, Identifiable, Codable {
    case appleOnDevice

    var id: String { rawValue }

    var displayTitle: String {
        "Apple On-Device"
    }
}

enum AppConfig {
    /// Default for iOS Simulator with local backend proxy.
    private static let defaultBaseURL = "https://coach-backend-proxy.onrender.com"
    private static let transcriptionMethodDefaultsKey = "transcriptionMethod"

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

    static var transcriptionMethod: TranscriptionMethod {
        if let envValue = ProcessInfo.processInfo.environment["TRANSCRIPTION_METHOD"],
           let method = TranscriptionMethod(rawValue: envValue),
           !envValue.isEmpty {
            return method
        }

        if let configured = UserDefaults.standard.string(forKey: transcriptionMethodDefaultsKey),
           let method = TranscriptionMethod(rawValue: configured),
           !configured.isEmpty {
            return method
        }

        return .appleOnDevice
    }

    static func setTranscriptionMethod(_ method: TranscriptionMethod) {
        UserDefaults.standard.set(method.rawValue, forKey: transcriptionMethodDefaultsKey)
    }

    static var vocabularyExtractURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("extract-from-audio")
    }

    static var vocabularyExamplesURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("examples")
    }

    static var vocabularyCloudURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("cloud")
    }

    static var speakingMissionURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("speaking-mission")
    }
}
