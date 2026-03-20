import Foundation

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
