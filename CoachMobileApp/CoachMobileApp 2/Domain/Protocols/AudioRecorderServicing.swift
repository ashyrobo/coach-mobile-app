import Foundation

protocol AudioRecorderServicing {
    func startRecording() async throws
    func pauseRecording() async throws
    func resumeRecording() async throws
    func stopRecording() async throws -> URL
    func currentRecordingTime() -> TimeInterval
}
