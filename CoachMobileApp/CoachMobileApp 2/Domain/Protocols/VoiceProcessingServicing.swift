import Foundation

protocol VoiceProcessingServicing {
    func processAudio(at audioURL: URL, mode: RewriteMode) async throws -> RewriteResult
    func extractVocabularyFromAudio(at audioURL: URL) async throws -> VocabularyExtractionResult
    func transcribePracticeAudio(at audioURL: URL) async throws -> String
    func generateVocabularyExamples(for phrase: String) async throws -> [String]
    func generateSpeakingMission(from phrases: [String]) async throws -> SpeakingMission
    func fetchCloudVocabulary() async throws -> [VocabularyItem]
    func replaceCloudVocabulary(with items: [VocabularyItem]) async throws
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

struct SpeakingMission: Codable {
    let prompt: String
    let requiredPhrases: [String]
    let sampleAnswer: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case requiredPhrases = "required_phrases"
        case sampleAnswer = "sample_answer"
    }
}
