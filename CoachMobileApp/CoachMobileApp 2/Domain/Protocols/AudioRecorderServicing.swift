import Foundation

struct LiveTranscriptionUpdate {
    let text: String
    let isFinal: Bool
}

protocol AudioRecorderServicing {
    func setLiveTranscriptionHandler(_ handler: ((LiveTranscriptionUpdate) -> Void)?)
    func setLiveTranscriptionAvailabilityHandler(_ handler: ((Bool) -> Void)?)
    func startRecording() async throws
    func pauseRecording() async throws
    func resumeRecording() async throws
    func stopRecording() async throws -> URL
    func currentRecordingTime() -> TimeInterval
}
