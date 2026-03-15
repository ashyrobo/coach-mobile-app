import Foundation

struct VoiceSession: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let audioPath: String
    let transcriptText: String
    let finalText: String
    let coachingTips: [String]
    let mode: RewriteMode

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        audioPath: String,
        transcriptText: String,
        finalText: String,
        coachingTips: [String],
        mode: RewriteMode
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioPath = audioPath
        self.transcriptText = transcriptText
        self.finalText = finalText
        self.coachingTips = coachingTips
        self.mode = mode
    }
}
