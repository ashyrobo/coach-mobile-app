import Foundation

struct ProcessVoiceSessionUseCase {
    private let voiceProcessingService: VoiceProcessingServicing

    init(voiceProcessingService: VoiceProcessingServicing) {
        self.voiceProcessingService = voiceProcessingService
    }

    func execute(audioURL: URL, mode: RewriteMode, tone: RewriteTone?) async throws -> RewriteResult {
        try await voiceProcessingService.processAudio(at: audioURL, mode: mode, tone: tone)
    }
}
