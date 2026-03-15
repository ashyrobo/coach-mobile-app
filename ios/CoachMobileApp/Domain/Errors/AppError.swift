import Foundation

enum AppError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recordingUnavailable
    case noRecordedAudio
    case invalidResponse
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required to record audio."
        case .speechPermissionDenied:
            return "Speech recognition permission is required to transcribe audio."
        case .recordingUnavailable:
            return "Recording is unavailable right now."
        case .noRecordedAudio:
            return "No recorded audio was found."
        case .invalidResponse:
            return "The server response could not be processed."
        case let .networkError(message):
            return "Network error: \(message)"
        case let .unknown(message):
            return message
        }
    }
}
