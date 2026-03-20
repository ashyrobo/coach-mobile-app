import Combine
import Foundation

@MainActor
final class VoiceSessionViewModel: ObservableObject {
    enum RecordingState {
        case idle
        case recording
        case paused
    }

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    @Published var transcriptionMethod: TranscriptionMethod = AppConfig.transcriptionMethod {
        didSet {
            AppConfig.setTranscriptionMethod(transcriptionMethod)
            applyTranscriptionMethodSelection()
        }
    }
    @Published var selectedMode: RewriteMode = .summarize
    @Published var statusMessage: String = "Ready to record"
    @Published var transcript: String = ""
    @Published var finalText: String = ""
    @Published var tips: [String] = []
    @Published var latestAudioURL: URL?
    @Published var lastProcessedMode: RewriteMode?
    @Published var realtimeStatusMessage: String = "Realtime idle"
    @Published var realtimeLiveText: String = ""
    @Published var isRealtimeRunning: Bool = false

    let historyStore: SessionHistoryStore
    let vocabularyStore: VocabularyStore

    private let permissionService: PermissionServicing
    private let audioRecorderService: AudioRecorderServicing
    private let processVoiceSessionUseCase: ProcessVoiceSessionUseCase
    private let realtimeStreamingService = OpenAIRealtimeStreamingService()
    private var recordingState: RecordingState = .idle
    private var recordingTimerCancellable: AnyCancellable?

    init(
        historyStore: SessionHistoryStore,
        vocabularyStore: VocabularyStore,
        permissionService: PermissionServicing,
        audioRecorderService: AudioRecorderServicing,
        voiceProcessingService: VoiceProcessingServicing
    ) {
        self.historyStore = historyStore
        self.vocabularyStore = vocabularyStore
        self.permissionService = permissionService
        self.audioRecorderService = audioRecorderService
        self.processVoiceSessionUseCase = ProcessVoiceSessionUseCase(voiceProcessingService: voiceProcessingService)
        applyTranscriptionMethodSelection()
    }

    convenience init() {
        self.init(
            historyStore: SessionHistoryStore(),
            vocabularyStore: VocabularyStore(),
            permissionService: PermissionService(),
            audioRecorderService: AudioRecorderService(),
            voiceProcessingService: VoiceProcessingAPIService()
        )
    }

    func startRecording() async {
        do {
            guard recordingState == .idle else { return }
            try await requestRequiredPermissions()
            try await audioRecorderService.startRecording()

            latestAudioURL = nil
            recordingTime = 0
            transcript = ""
            finalText = ""
            tips = []
            recordingState = .recording
            isRecording = true
            isPaused = false
            statusMessage = "Recording in progress..."
            startRecordingTimer()
        } catch {
            statusMessage = error.localizedDescription
            resetRecordingUIState()
        }
    }

    func pauseRecording() async {
        do {
            guard recordingState == .recording else { return }
            try await audioRecorderService.pauseRecording()

            recordingState = .paused
            isPaused = true
            isRecording = false
            statusMessage = "Recording paused."
            stopRecordingTimer()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resumeRecording() async {
        do {
            guard recordingState == .paused else { return }
            try await audioRecorderService.resumeRecording()

            recordingState = .recording
            isPaused = false
            isRecording = true
            statusMessage = "Recording resumed..."
            startRecordingTimer()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        do {
            guard recordingState != .idle else { return }
            latestAudioURL = try await audioRecorderService.stopRecording()
            recordingTime = audioRecorderService.currentRecordingTime()
            statusMessage = "Recording stopped. Ready to process."
        } catch {
            statusMessage = error.localizedDescription
        }

        recordingState = .idle
        isRecording = false
        isPaused = false
        stopRecordingTimer()
    }

    func toggleRecording() async {
        switch recordingState {
        case .idle:
            await startRecording()
        case .recording, .paused:
            await stopRecording()
        }
    }

    func processCurrentSession() async {
        guard let audioURL = latestAudioURL else {
            statusMessage = AppError.noRecordedAudio.localizedDescription
            return
        }

        statusMessage = "Processing..."
        do {
            let result = try await processVoiceSessionUseCase.execute(audioURL: audioURL, mode: selectedMode)
            let savedAudioURL = try historyStore.persistRecording(from: audioURL)
            let session = VoiceSession(
                audioPath: savedAudioURL.path,
                sessionTitle: result.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                transcriptText: result.transcript,
                finalText: result.finalText,
                coachingTips: result.tips,
                mode: selectedMode
            )
            try historyStore.saveSession(session)

            transcript = result.transcript
            finalText = result.finalText
            tips = result.tips
            latestAudioURL = savedAudioURL
            lastProcessedMode = selectedMode
            statusMessage = "Done"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addVocabularyFromWordImprovement(_ phrase: String) -> VocabularyStore.ManualAddOutcome {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return .invalid }

        let correctedSentence = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctedSentence.isEmpty else { return .invalid }

        let spokenSentence = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceSentence = spokenSentence.isEmpty ? correctedSentence : spokenSentence
        let mode = lastProcessedMode ?? selectedMode

        do {
            let outcome = try vocabularyStore.addManualVocabulary(
                phrase: trimmedPhrase,
                spokenSentence: sourceSentence,
                correctedSentence: correctedSentence,
                mode: mode
            )

            switch outcome {
            case .added:
                statusMessage = "Added to vocabulary"
            case .alreadyExists:
                statusMessage = "Already in vocabulary"
            case .invalid:
                statusMessage = "Unable to add vocabulary"
            }

            return outcome
        } catch {
            statusMessage = "Unable to save vocabulary right now"
            return .invalid
        }
    }

    private func requestRequiredPermissions() async throws {
        let micAllowed = await permissionService.requestMicrophonePermission()
        guard micAllowed else { throw AppError.microphonePermissionDenied }

        let speechAllowed = await permissionService.requestSpeechPermission()
        guard speechAllowed else { throw AppError.speechPermissionDenied }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        recordingTimerCancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.recordingTime = self.audioRecorderService.currentRecordingTime()
            }
    }

    private func stopRecordingTimer() {
        recordingTimerCancellable?.cancel()
        recordingTimerCancellable = nil
    }

    private func resetRecordingUIState() {
        recordingState = .idle
        isRecording = false
        isPaused = false
        stopRecordingTimer()
    }

    private func applyTranscriptionMethodSelection() {
        _ = transcriptionMethod
    }

    func startRealtimeStreaming() async {
        do {
            try await requestRequiredPermissions()
            realtimeLiveText = ""
            realtimeStatusMessage = "Connecting to realtime..."

            try await realtimeStreamingService.start { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }

                    switch event {
                    case let .textDelta(chunk):
                        self.realtimeLiveText += chunk
                    case let .status(message):
                        self.realtimeStatusMessage = message
                    case let .error(message):
                        self.realtimeStatusMessage = message
                    }
                }
            }

            isRealtimeRunning = true
            realtimeStatusMessage = "Realtime streaming"
        } catch {
            isRealtimeRunning = false
            realtimeStatusMessage = error.localizedDescription
        }
    }

    func stopRealtimeStreaming() {
        realtimeStreamingService.stop()
        isRealtimeRunning = false
        if realtimeStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            realtimeStatusMessage = "Realtime stopped"
        }
    }
}

final class SessionHistoryStore: ObservableObject {
    @Published private(set) var sessions: [VoiceSession] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var sessionsFileURL: URL {
        documentsDirectory.appendingPathComponent("voice-sessions.json")
    }

    private var recordingsDirectoryURL: URL {
        documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted]
        loadSessions()
    }

    func persistRecording(from sourceURL: URL) throws -> URL {
        try ensureRecordingsDirectoryExists()

        if sourceURL.path.hasPrefix(recordingsDirectoryURL.path) {
            return sourceURL
        }

        let destinationURL = recordingsDirectoryURL
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func saveSession(_ session: VoiceSession) throws {
        sessions.insert(session, at: 0)
        try persistSessions()
    }

    func deleteSession(_ session: VoiceSession) throws {
        sessions.removeAll { $0.id == session.id }

        let audioURL = URL(fileURLWithPath: session.audioPath)
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }

        try persistSessions()
    }

    func deleteSessionSafely(_ session: VoiceSession) {
        do {
            try deleteSession(session)
        } catch {
            print("Failed to delete session: \(error.localizedDescription)")
        }
    }

    private func ensureRecordingsDirectoryExists() throws {
        if !fileManager.fileExists(atPath: recordingsDirectoryURL.path) {
            try fileManager.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func loadSessions() {
        guard fileManager.fileExists(atPath: sessionsFileURL.path) else {
            sessions = []
            return
        }

        do {
            let data = try Data(contentsOf: sessionsFileURL)
            sessions = try decoder.decode([VoiceSession].self, from: data)
            sessions.sort { $0.createdAt > $1.createdAt }
        } catch {
            sessions = []
            print("Failed to load sessions: \(error.localizedDescription)")
        }
    }

    private func persistSessions() throws {
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsFileURL, options: .atomic)
    }
}

struct VocabularyItem: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let sourceSessionID: UUID
    let phrase: String
    let tag: String?
    let meaning: String
    let spokenSentence: String
    let correctedSentence: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceSessionID: UUID,
        phrase: String,
        tag: String? = nil,
        meaning: String,
        spokenSentence: String,
        correctedSentence: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceSessionID = sourceSessionID
        self.phrase = phrase
        self.tag = tag
        self.meaning = meaning
        self.spokenSentence = spokenSentence
        self.correctedSentence = correctedSentence
    }
}

final class VocabularyStore: ObservableObject {
    enum ManualAddOutcome {
        case added
        case alreadyExists
        case invalid
    }

    @Published private(set) var items: [VocabularyItem] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var vocabularyFileURL: URL {
        documentsDirectory.appendingPathComponent("vocabulary-items.json")
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted]
        loadItems()
    }

    func autoSaveVocabulary(from session: VoiceSession) throws {
        let generatedItems = extractVocabularyItems(from: session)
        guard !generatedItems.isEmpty else { return }

        for item in generatedItems {
            let alreadyExists = items.contains {
                $0.sourceSessionID == item.sourceSessionID &&
                $0.phrase.caseInsensitiveCompare(item.phrase) == .orderedSame &&
                $0.correctedSentence.caseInsensitiveCompare(item.correctedSentence) == .orderedSame
            }

            if !alreadyExists {
                items.insert(item, at: 0)
            }
        }

        items.sort { $0.createdAt > $1.createdAt }
        try persistItems()
    }

    func addManualVocabulary(
        phrase: String,
        spokenSentence: String,
        correctedSentence: String,
        mode: RewriteMode,
        sourceSessionID: UUID = UUID()
    ) throws -> ManualAddOutcome {
        let cleanPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCorrectedSentence = correctedSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSpokenSentence = spokenSentence.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanPhrase.isEmpty, !cleanCorrectedSentence.isEmpty else {
            return .invalid
        }

        let alreadyExists = items.contains {
            $0.phrase.caseInsensitiveCompare(cleanPhrase) == .orderedSame
            && $0.correctedSentence.caseInsensitiveCompare(cleanCorrectedSentence) == .orderedSame
        }

        if alreadyExists {
            return .alreadyExists
        }

        let item = VocabularyItem(
            sourceSessionID: sourceSessionID,
            phrase: cleanPhrase,
            tag: vocabularyTag(for: mode),
            meaning: "Saved from word improvements.",
            spokenSentence: cleanSpokenSentence.isEmpty ? cleanCorrectedSentence : cleanSpokenSentence,
            correctedSentence: cleanCorrectedSentence
        )

        items.insert(item, at: 0)
        items.sort { $0.createdAt > $1.createdAt }
        try persistItems()
        return .added
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        do {
            try persistItems()
        } catch {
            print("Failed to persist vocabulary delete: \(error.localizedDescription)")
        }
    }

    private func loadItems() {
        guard fileManager.fileExists(atPath: vocabularyFileURL.path) else {
            items = []
            return
        }

        do {
            let data = try Data(contentsOf: vocabularyFileURL)
            items = try decoder.decode([VocabularyItem].self, from: data)
            items.sort { $0.createdAt > $1.createdAt }
        } catch {
            items = []
            print("Failed to load vocabulary items: \(error.localizedDescription)")
        }
    }

    private func persistItems() throws {
        let data = try encoder.encode(items)
        try data.write(to: vocabularyFileURL, options: .atomic)
    }

    private func extractVocabularyItems(from session: VoiceSession) -> [VocabularyItem] {
        let spokenSentences = splitIntoSentences(session.transcriptText)
        let correctedSentences = splitIntoSentences(session.finalText)
        let pairCount = max(spokenSentences.count, correctedSentences.count)

        var generated: [VocabularyItem] = []
        generated.reserveCapacity(max(1, pairCount))

        for index in 0..<pairCount {
            let spoken = (index < spokenSentences.count ? spokenSentences[index] : session.transcriptText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = (index < correctedSentences.count ? correctedSentences[index] : session.finalText)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !corrected.isEmpty else { continue }

            let phrase = candidatePhrase(spoken: spoken, corrected: corrected)
            guard !phrase.isEmpty else { continue }

            let meaning: String
            if !spoken.isEmpty {
                meaning = "More natural way to express your idea from: \"\(truncate(spoken, maxLength: 90))\""
            } else {
                meaning = "Useful phrase from your corrected sentence."
            }

            generated.append(
                VocabularyItem(
                    sourceSessionID: session.id,
                    phrase: phrase,
                    tag: vocabularyTag(for: session.mode),
                    meaning: meaning,
                    spokenSentence: spoken.isEmpty ? session.transcriptText : spoken,
                    correctedSentence: corrected
                )
            )
        }

        if generated.isEmpty {
            let fallbackPhrase = candidatePhrase(spoken: session.transcriptText, corrected: session.finalText)
            if !fallbackPhrase.isEmpty {
                generated.append(
                    VocabularyItem(
                        sourceSessionID: session.id,
                        phrase: fallbackPhrase,
                        tag: vocabularyTag(for: session.mode),
                        meaning: "Useful phrase extracted from your processed session.",
                        spokenSentence: session.transcriptText,
                        correctedSentence: session.finalText
                    )
                )
            }
        }

        return Array(generated.prefix(5))
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { [".", "!", "?"].contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func candidatePhrase(spoken: String, corrected: String) -> String {
        let cleanCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCorrected.isEmpty else { return "" }

        let spokenWords = Set(tokenize(spoken).map { $0.lowercased() })
        let correctedWords = tokenize(cleanCorrected)

        let newWords = correctedWords.filter { !spokenWords.contains($0.lowercased()) }
        if !newWords.isEmpty {
            return newWords.prefix(4).joined(separator: " ")
        }

        if cleanCorrected.caseInsensitiveCompare(spoken.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
            return correctedWords.prefix(4).joined(separator: " ")
        }

        return ""
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = text.prefix(maxLength)
        return "\(prefix)…"
    }

    private func vocabularyTag(for mode: RewriteMode) -> String {
        switch mode {
        case .summarize:
            return "Summary"
        case .rewordBetter:
            return "Fluency"
        }
    }
}
