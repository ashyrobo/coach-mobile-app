import Foundation

enum RewriteMode: String, CaseIterable, Identifiable, Codable {
    case summarize
    case fullSentence
    case rewordBetter

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .summarize: return "Summarize"
        case .fullSentence: return "Full Sentence"
        case .rewordBetter: return "Reword Better"
        }
    }
}
