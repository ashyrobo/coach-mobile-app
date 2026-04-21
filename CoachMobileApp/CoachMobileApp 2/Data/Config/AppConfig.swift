import Foundation

enum TranscriptionMethod: String, CaseIterable, Identifiable, Codable {
    case appleOnDevice

    var id: String { rawValue }

    var displayTitle: String {
        "Backend Proxy (OpenAI)"
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

    static var adaptiveSpeakingMissionURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("mission")
            .appendingPathComponent("generate-adaptive")
    }

    static var vocabularyActivationEvaluateURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("activation")
            .appendingPathComponent("evaluate")
    }

    static var shadowingParagraphURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("vocabulary")
            .appendingPathComponent("shadowing-paragraph")
    }

    static var shadowingPromptWithAudioURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("practice")
            .appendingPathComponent("shadowing-prompt-with-audio")
    }

    static var shadowingTTSVoice: String {
        let envValue = ProcessInfo.processInfo.environment["SHADOWING_TTS_VOICE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (envValue?.isEmpty == false ? envValue : nil) ?? "alloy"
    }

    static var shadowingTTSFormat: String {
        let envValue = ProcessInfo.processInfo.environment["SHADOWING_TTS_FORMAT"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (envValue?.isEmpty == false ? envValue : nil) ?? "mp3"
    }

    static var shadowingTTSSpeed: Double {
        let envValue = ProcessInfo.processInfo.environment["SHADOWING_TTS_SPEED"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envValue,
           let numeric = Double(envValue),
           numeric.isFinite {
            return min(2.0, max(0.25, numeric))
        }

        return 1.0
    }

    static var behavioralQuestionURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("interview")
            .appendingPathComponent("behavioral")
            .appendingPathComponent("question")
    }

    static var behavioralEvaluationURL: URL {
        voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("interview")
            .appendingPathComponent("behavioral")
            .appendingPathComponent("evaluate")
    }
}
