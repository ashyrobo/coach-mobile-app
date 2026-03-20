import AVFoundation
import Foundation

final class AudioRecorderService: NSObject, AudioRecorderServicing {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var lastRecordingDuration: TimeInterval = 0

    override init() {
        super.init()
    }

    func startRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = makeRecordingURL()
        currentURL = url
        lastRecordingDuration = 0

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

    func pauseRecording() async throws {
        guard let recorder, recorder.isRecording else {
            throw AppError.noRecordedAudio
        }
        recorder.pause()
    }

    func resumeRecording() async throws {
        guard let recorder, currentURL != nil else {
            throw AppError.noRecordedAudio
        }

        guard recorder.record() else {
            throw AppError.recordingUnavailable
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder, let currentURL else {
            throw AppError.noRecordedAudio
        }
        lastRecordingDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return currentURL
    }

    func currentRecordingTime() -> TimeInterval {
        recorder?.currentTime ?? lastRecordingDuration
    }

    private func makeRecordingURL() -> URL {
        let fileName = "recording-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
