import Combine
import Foundation

@MainActor
final class VoiceSessionViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var selectedMode: RewriteMode = .summarize
    @Published var statusMessage: String = "Ready to record"
    @Published var transcript: String = ""
    @Published var finalText: String = ""
    @Published var tips: [String] = []
    @Published var latestAudioURL: URL?

    private let permissionService: PermissionServicing
    private let audioRecorderService: AudioRecorderServicing
    private let processVoiceSessionUseCase: ProcessVoiceSessionUseCase

    init(
        permissionService: PermissionServicing = PermissionService(),
        audioRecorderService: AudioRecorderServicing = AudioRecorderService(),
        voiceProcessingService: VoiceProcessingServicing = VoiceProcessingAPIService()
    ) {
        self.permissionService = permissionService
        self.audioRecorderService = audioRecorderService
        self.processVoiceSessionUseCase = ProcessVoiceSessionUseCase(voiceProcessingService: voiceProcessingService)
    }

    func toggleRecording() async {
        do {
            if isRecording {
                latestAudioURL = try await audioRecorderService.stopRecording()
                isRecording = false
                statusMessage = "Recording stopped. Ready to process."
            } else {
                try await requestRequiredPermissions()
                try await audioRecorderService.startRecording()
                isRecording = true
                statusMessage = "Recording... tap again to stop"
            }
        } catch {
            statusMessage = error.localizedDescription
            isRecording = false
        }
    }

    func processCurrentSession() async {
        guard let audioURL = latestAudioURL else {
            statusMessage = AppError.noRecordedAudio.localizedDescription
            return
        }

        statusMessage = "Processing..."
        do {
            let result = try await processVoiceSessionUseCase.execute(audioURL: audioURL, mode: selectedMode)
            transcript = result.transcript
            finalText = result.finalText
            tips = result.tips
            statusMessage = "Done"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func requestRequiredPermissions() async throws {
        let micAllowed = await permissionService.requestMicrophonePermission()
        guard micAllowed else { throw AppError.microphonePermissionDenied }

        let speechAllowed = await permissionService.requestSpeechPermission()
        guard speechAllowed else { throw AppError.speechPermissionDenied }
    }
}

