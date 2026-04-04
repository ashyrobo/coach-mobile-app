import Foundation

protocol VoiceProcessingServicing {
    func processAudio(at audioURL: URL, mode: RewriteMode, tone: RewriteTone?) async throws -> RewriteResult
    func extractVocabularyFromAudio(at audioURL: URL) async throws -> VocabularyExtractionResult
    func transcribePracticeAudio(at audioURL: URL) async throws -> String
    func generateVocabularyExamples(for phrase: String) async throws -> [String]
    func generateSpeakingMission(from phrases: [String]) async throws -> SpeakingMission
    func generateBehavioralQuestion(category: BehavioralQuestionCategory) async throws -> BehavioralQuestion
    func evaluateBehavioralAnswer(question: BehavioralQuestion, answerTranscript: String) async throws -> BehavioralEvaluation
    func fetchCloudVocabulary() async throws -> [VocabularyItem]
    func replaceCloudVocabulary(with items: [VocabularyItem]) async throws
}

enum BehavioralQuestionCategory: String, CaseIterable, Identifiable, Codable {
    case mixed
    case leadership
    case conflict
    case failure
    case ownership
    case teamwork
    case ambiguity
    case impact

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .mixed: return "Mixed"
        case .leadership: return "Leadership"
        case .conflict: return "Conflict"
        case .failure: return "Failure"
        case .ownership: return "Ownership"
        case .teamwork: return "Teamwork"
        case .ambiguity: return "Ambiguity"
        case .impact: return "Impact"
        }
    }
}

struct BehavioralQuestion: Codable {
    let prompt: String
    let category: BehavioralQuestionCategory
    let focus: String
}

struct BehavioralSTARCoverage: Codable {
    let situation: Bool
    let task: Bool
    let action: Bool
    let result: Bool
}

struct BehavioralRubricScores: Codable {
    let clarity: Int
    let ownership: Int
    let specificity: Int
    let impact: Int
    let conciseness: Int
}

struct BehavioralEvaluation: Codable {
    let summaryFeedback: String
    let starCoverage: BehavioralSTARCoverage
    let rubric: BehavioralRubricScores
    let improvedAnswer: String
    let followUpQuestions: [String]

    enum CodingKeys: String, CodingKey {
        case summaryFeedback = "summary_feedback"
        case starCoverage = "star_coverage"
        case rubric
        case improvedAnswer = "improved_answer"
        case followUpQuestions = "follow_up_questions"
    }
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
