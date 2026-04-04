import Foundation

enum RewriteTone: String, CaseIterable, Identifiable, Codable {
    case professional
    case casual
    case friendly
    case confident
    case polite

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .friendly: return "Friendly"
        case .confident: return "Confident"
        case .polite: return "Polite"
        }
    }
}

enum RewriteMode: String, CaseIterable, Identifiable, Codable {
    case summarize
    case rewordBetter

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .summarize: return "Summarize"
        case .rewordBetter: return "Reword Better"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        // Backward compatibility for previously saved sessions.
        if raw == "fullSentence" {
            self = .summarize
            return
        }

        guard let mode = RewriteMode(rawValue: raw) else {
            self = .summarize
            return
        }
        self = mode
    }
}
