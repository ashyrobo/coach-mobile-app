import Foundation

struct RewriteResult: Codable {
    let transcript: String
    let finalText: String
    let tips: [String]
    let grammarFixes: [String]

    enum CodingKeys: String, CodingKey {
        case transcript
        case finalText = "final_text"
        case tips
        case grammarFixes = "grammar_fixes"
    }
}
