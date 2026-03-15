import AVFoundation
import Foundation

final class AudioRecorderService: NSObject, AudioRecorderServicing {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func startRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = makeRecordingURL()
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder?.record() == true else {
            throw AppError.recordingUnavailable
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder, recorder.isRecording, let currentURL else {
            throw AppError.noRecordedAudio
        }
        recorder.stop()
        self.recorder = nil
        return currentURL
    }

    private func makeRecordingURL() -> URL {
        let fileName = "recording-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
