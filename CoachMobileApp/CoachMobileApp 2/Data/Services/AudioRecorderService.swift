import AVFoundation
import Foundation
import Speech

final class AudioRecorderService: NSObject, AudioRecorderServicing, SFSpeechRecognizerDelegate {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var lastRecordingDuration: TimeInterval = 0
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveTranscriptionHandler: ((LiveTranscriptionUpdate) -> Void)?
    private var liveTranscriptionAvailabilityHandler: ((Bool) -> Void)?

    override init() {
        super.init()
        speechRecognizer?.delegate = self
        publishTranscriptionAvailability()
    }

    func setLiveTranscriptionHandler(_ handler: ((LiveTranscriptionUpdate) -> Void)?) {
        liveTranscriptionHandler = handler
    }

    func setLiveTranscriptionAvailabilityHandler(_ handler: ((Bool) -> Void)?) {
        liveTranscriptionAvailabilityHandler = handler
        publishTranscriptionAvailability()
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

        try startLiveTranscription()
    }

    func pauseRecording() async throws {
        guard let recorder, recorder.isRecording else {
            throw AppError.noRecordedAudio
        }
        recorder.pause()
        audioEngine.pause()
    }

    func resumeRecording() async throws {
        guard let recorder, currentURL != nil else {
            throw AppError.noRecordedAudio
        }

        guard recorder.record() else {
            throw AppError.recordingUnavailable
        }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder, let currentURL else {
            throw AppError.noRecordedAudio
        }
        lastRecordingDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        stopLiveTranscription()
        return currentURL
    }

    func currentRecordingTime() -> TimeInterval {
        recorder?.currentTime ?? lastRecordingDuration
    }

    private func makeRecordingURL() -> URL {
        let fileName = "recording-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func startLiveTranscription() throws {
        stopLiveTranscription()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            publishTranscriptionAvailability(false)
            return
        }

        publishTranscriptionAvailability()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async {
                    self?.liveTranscriptionHandler?(
                        LiveTranscriptionUpdate(
                            text: result.bestTranscription.formattedString,
                            isFinal: result.isFinal
                        )
                    )
                }
            }

            if error != nil {
                self?.recognitionRequest?.endAudio()
            }
        }
    }

    private func stopLiveTranscription() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        publishTranscriptionAvailability(available)
    }

    private func publishTranscriptionAvailability(_ forceAvailability: Bool? = nil) {
        let availability = forceAvailability ?? {
            guard let speechRecognizer else { return false }
            if #available(iOS 13.0, *) {
                return speechRecognizer.isAvailable && speechRecognizer.supportsOnDeviceRecognition
            } else {
                return false
            }
        }()
        DispatchQueue.main.async { [weak self] in
            self?.liveTranscriptionAvailabilityHandler?(availability)
        }
    }
}
