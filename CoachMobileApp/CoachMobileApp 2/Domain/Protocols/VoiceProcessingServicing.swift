import Foundation

protocol VoiceProcessingServicing {
    func processAudio(at audioURL: URL, mode: RewriteMode) async throws -> RewriteResult
    func extractVocabularyFromAudio(at audioURL: URL) async throws -> VocabularyExtractionResult
    func generateVocabularyExamples(for phrase: String) async throws -> [String]
}

struct VocabularyExtractionResult: Codable {
    let transcript: String
    let phrase: String
    let meaning: String
    let correctedSentence: String

    enum CodingKeys: String, CodingKey {
        case transcript
        case phrase
        case meaning
        case correctedSentence = "corrected_sentence"
    }
}
