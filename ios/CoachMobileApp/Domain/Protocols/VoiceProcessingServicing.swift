import Foundation

protocol VoiceProcessingServicing {
    func processAudio(at audioURL: URL, mode: RewriteMode) async throws -> RewriteResult
}
