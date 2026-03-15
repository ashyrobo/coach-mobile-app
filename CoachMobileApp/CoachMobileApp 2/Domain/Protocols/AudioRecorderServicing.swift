import Foundation

protocol AudioRecorderServicing {
    func startRecording() async throws
    func stopRecording() async throws -> URL
}
