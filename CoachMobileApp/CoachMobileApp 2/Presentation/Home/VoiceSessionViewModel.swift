import Combine
import AVFoundation
import Foundation
import UserNotifications

enum VocabularyFlashcardState: String, Codable {
    case new
    case learning
    case review
}

enum VocabularyReviewRating {
    case again
    case good
    case easy
}

enum VocabularyReviewRatingRecord: String, Codable {
    case again
    case good
    case easy
}

@MainActor
final class VoiceSessionViewModel: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
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
    @Published var selectedRewriteTone: RewriteTone = .professional
    @Published var statusMessage: String = "Ready to record"
    @Published var transcript: String = ""
    @Published var finalText: String = ""
    @Published var tips: [String] = []
    @Published var latestAudioURL: URL?
    @Published var lastProcessedMode: RewriteMode?
    @Published var isVocabularyVoiceRecording: Bool = false
    @Published var vocabularyVoiceStatusMessage: String = ""
    @Published var vocabularyExamplesByItemID: [UUID: [String]] = [:]
    @Published var vocabularyExamplesLoadingID: UUID?
    @Published var vocabularyPracticeQueue: [VocabularyItem] = []
    @Published var vocabularyPracticeCurrentItem: VocabularyItem?
    @Published var vocabularyPracticeSessionInitialCount: Int = 0
    @Published var isVocabularyPracticeAnswerRevealed: Bool = false
    @Published var vocabularyPracticeReviewedToday: Int = 0
    @Published var vocabularyPracticeDueCount: Int = 0
    @Published var isVocabularyPracticeActive: Bool = false
    @Published var vocabularyReminderEnabled: Bool = false {
        didSet {
            defaults.set(vocabularyReminderEnabled, forKey: Self.vocabularyReminderEnabledKey)
            Task { await updateVocabularyReminderSchedule() }
        }
    }
    @Published var vocabularyReminderHour: Int = 20 {
        didSet {
            defaults.set(vocabularyReminderHour, forKey: Self.vocabularyReminderHourKey)
            if vocabularyReminderEnabled {
                Task { await updateVocabularyReminderSchedule() }
            }
        }
    }
    @Published var vocabularyReminderMinute: Int = 0 {
        didSet {
            defaults.set(vocabularyReminderMinute, forKey: Self.vocabularyReminderMinuteKey)
            if vocabularyReminderEnabled {
                Task { await updateVocabularyReminderSchedule() }
            }
        }
    }
    @Published var shadowingPromptText: String = ""
    @Published var shadowingRequiredPhrases: [String] = []
    @Published var isGeneratingShadowingPrompt: Bool = false
    @Published var isShadowingRecording: Bool = false
    @Published var isShadowingPromptPlaying: Bool = false
    @Published var shadowingTranscript: String = ""
    @Published var shadowingFeedbackMessage: String = ""
    @Published var shadowingScore: Int = 0
    @Published var currentSpeakingMission: SpeakingMission?
    @Published var isGeneratingSpeakingMission: Bool = false
    @Published var isMissionRecording: Bool = false
    @Published var missionTranscript: String = ""
    @Published var missionFeedbackMessage: String = ""
    @Published var missionCoverageCount: Int = 0
    @Published var missionCoverageTotal: Int = 0
    @Published var selectedBehavioralCategory: BehavioralQuestionCategory = .mixed
    @Published var currentBehavioralQuestion: BehavioralQuestion?
    @Published var isGeneratingBehavioralQuestion: Bool = false
    @Published var isBehavioralAnswerRecording: Bool = false
    @Published var behavioralAnswerTranscript: String = ""
    @Published var isEvaluatingBehavioralAnswer: Bool = false
    @Published var behavioralEvaluation: BehavioralEvaluation?
    @Published var behavioralStatusMessage: String = ""

    let historyStore: SessionHistoryStore
    let vocabularyStore: VocabularyStore

    private let permissionService: PermissionServicing
    private let audioRecorderService: AudioRecorderServicing
    private let processVoiceSessionUseCase: ProcessVoiceSessionUseCase
    private let voiceProcessingService: VoiceProcessingServicing
    private let vocabularyAudioRecorderService: AudioRecorderServicing
    private let speakingPracticeAudioRecorderService: AudioRecorderServicing
    private let behavioralAudioRecorderService: AudioRecorderServicing
    private let defaults = UserDefaults.standard
    private static let vocabularyReminderEnabledKey = "vocabulary-reminder-enabled"
    private static let vocabularyReminderHourKey = "vocabulary-reminder-hour"
    private static let vocabularyReminderMinuteKey = "vocabulary-reminder-minute"
    private static let vocabularyReminderNotificationID = "vocabulary-daily-reminder"
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var recordingState: RecordingState = .idle
    private var recordingTimerCancellable: AnyCancellable?
    private var lastShadowingPhraseSet: Set<String> = []

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
        self.voiceProcessingService = voiceProcessingService
        self.vocabularyAudioRecorderService = AudioRecorderService()
        self.speakingPracticeAudioRecorderService = AudioRecorderService()
        self.behavioralAudioRecorderService = AudioRecorderService()
        self.processVoiceSessionUseCase = ProcessVoiceSessionUseCase(voiceProcessingService: voiceProcessingService)
        super.init()
        speechSynthesizer.delegate = self
        applyTranscriptionMethodSelection()
        hydrateVocabularyReminderSettings()
        hydrateVocabularyExamplesCache()
        refreshVocabularyPracticeStats()

        Task { [weak self] in
            await self?.syncVocabularyFromCloud()
            await self?.ensureShadowingPromptReady()
        }
    }

    override convenience init() {
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
            let tone = selectedMode == .rewordBetter ? selectedRewriteTone : nil
            let result = try await processVoiceSessionUseCase.execute(audioURL: audioURL, mode: selectedMode, tone: tone)
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
            let meaning = meaningForWordImprovementSuggestion(
                phrase: trimmedPhrase,
                spokenSentence: sourceSentence,
                correctedSentence: correctedSentence
            )

            let outcome = try vocabularyStore.addManualVocabulary(
                phrase: trimmedPhrase,
                spokenSentence: sourceSentence,
                correctedSentence: correctedSentence,
                mode: mode,
                meaningOverride: meaning
            )

            switch outcome {
            case .added:
                statusMessage = "Added to vocabulary"
                Task { await syncVocabularyToCloud() }
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

    private func meaningForWordImprovementSuggestion(
        phrase: String,
        spokenSentence: String,
        correctedSentence: String
    ) -> String {
        let cleanPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSpoken = spokenSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCorrected = correctedSentence.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanSpoken.isEmpty, cleanSpoken.caseInsensitiveCompare(cleanCorrected) != .orderedSame {
            return "\"\(cleanPhrase)\" improves how you originally said: \"\(truncateMeaningContext(cleanSpoken, maxLength: 90))\""
        }

        if !cleanCorrected.isEmpty {
            return "Useful phrase from your improved sentence: \"\(truncateMeaningContext(cleanCorrected, maxLength: 90))\""
        }

        return "Useful phrase from your processed session."
    }

    private func truncateMeaningContext(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return "\(text.prefix(maxLength))…"
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

    func startVocabularyVoiceCapture() async {
        do {
            guard !isVocabularyVoiceRecording else { return }
            try await requestRequiredPermissions()
            try await vocabularyAudioRecorderService.startRecording()

            isVocabularyVoiceRecording = true
            vocabularyVoiceStatusMessage = "Listening..."
        } catch {
            isVocabularyVoiceRecording = false
            vocabularyVoiceStatusMessage = error.localizedDescription
        }
    }

    func stopVocabularyVoiceCaptureAndSave() async {
        guard isVocabularyVoiceRecording else { return }

        do {
            let audioURL = try await vocabularyAudioRecorderService.stopRecording()
            isVocabularyVoiceRecording = false
            vocabularyVoiceStatusMessage = "Processing spoken phrase..."

            let extracted = try await voiceProcessingService.extractVocabularyFromAudio(at: audioURL)

            let phrase = extracted.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = extracted.correctedSentence.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !phrase.isEmpty, !corrected.isEmpty else {
                vocabularyVoiceStatusMessage = "Could not detect a clear word or phrase. Try again."
                return
            }

            let outcome = try vocabularyStore.addManualVocabulary(
                phrase: phrase,
                spokenSentence: extracted.transcript,
                correctedSentence: corrected,
                mode: .rewordBetter,
                meaningOverride: extracted.meaning
            )

            switch outcome {
            case .added:
                vocabularyVoiceStatusMessage = "Added \"\(phrase)\" to Vocabulary"
                await syncVocabularyToCloud()
            case .alreadyExists:
                vocabularyVoiceStatusMessage = "\"\(phrase)\" is already in Vocabulary"
            case .invalid:
                vocabularyVoiceStatusMessage = "Could not save this vocabulary item"
            }
        } catch {
            isVocabularyVoiceRecording = false
            vocabularyVoiceStatusMessage = "Unable to process voice add: \(error.localizedDescription)"
        }
    }

    func vocabularyExamples(for item: VocabularyItem) -> [String] {
        if let cached = vocabularyExamplesByItemID[item.id], !cached.isEmpty {
            return cached
        }
        return item.exampleSentences
    }

    func loadVocabularyExamples(for item: VocabularyItem) async {
        if let cached = vocabularyExamplesByItemID[item.id], !cached.isEmpty { return }
        if !item.exampleSentences.isEmpty {
            vocabularyExamplesByItemID[item.id] = item.exampleSentences
            return
        }

        let phrase = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }

        vocabularyExamplesLoadingID = item.id
        defer {
            if vocabularyExamplesLoadingID == item.id {
                vocabularyExamplesLoadingID = nil
            }
        }

        do {
            let examples = try await voiceProcessingService.generateVocabularyExamples(for: phrase)
            guard !examples.isEmpty else { return }
            vocabularyExamplesByItemID[item.id] = examples
            vocabularyStore.updateExamples(for: item.id, examples: examples)
            await syncVocabularyToCloud()
        } catch {
            vocabularyVoiceStatusMessage = "Could not load examples for \"\(phrase)\""
        }
    }

    func syncVocabularyFromCloud() async {
        do {
            let localItems = vocabularyStore.items
            let cloudItems = try await voiceProcessingService.fetchCloudVocabulary()

            if cloudItems.isEmpty, !localItems.isEmpty {
                try await voiceProcessingService.replaceCloudVocabulary(with: localItems)
                vocabularyVoiceStatusMessage = "Uploaded local vocabulary to cloud"
                return
            }

            vocabularyStore.replaceAllItems(with: cloudItems)
            hydrateVocabularyExamplesCache()
            refreshVocabularyPracticeStats()
            if !cloudItems.isEmpty {
                vocabularyVoiceStatusMessage = "Vocabulary synced from cloud"
            }
        } catch {
            vocabularyVoiceStatusMessage = "Cloud sync download failed"
        }
    }

    func syncVocabularyToCloud() async {
        do {
            try await voiceProcessingService.replaceCloudVocabulary(with: vocabularyStore.items)
        } catch {
            vocabularyVoiceStatusMessage = "Cloud sync upload failed"
        }
    }

    func deleteVocabularyItem(id: UUID, maxNewCardsPerDay: Int = 5) {
        vocabularyStore.deleteItem(id: id)
        refreshVocabularyPracticeStats(maxNewCardsPerDay: maxNewCardsPerDay)
        Task {
            await syncVocabularyToCloud()
            await ensureShadowingPromptReady(forceRegenerate: true)
        }
    }

    private func hydrateVocabularyExamplesCache() {
        var cache: [UUID: [String]] = [:]
        for item in vocabularyStore.items where !item.exampleSentences.isEmpty {
            cache[item.id] = item.exampleSentences
        }
        vocabularyExamplesByItemID = cache
    }

    func ensureShadowingPromptReady(forceRegenerate: Bool = false) async {
        if !forceRegenerate,
           !shadowingPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !shadowingRequiredPhrases.isEmpty {
            return
        }

        await generateNextShadowingPrompt()
    }

    func generateNextShadowingPrompt() async {
        let selectedPhrases = selectRandomShadowingPhrases(targetCount: 8)
        guard !selectedPhrases.isEmpty else {
            shadowingPromptText = ""
            shadowingRequiredPhrases = []
            shadowingFeedbackMessage = "Add vocabulary items first to generate a shadowing paragraph."
            return
        }

        isGeneratingShadowingPrompt = true
        defer { isGeneratingShadowingPrompt = false }

        do {
            let generated = try await voiceProcessingService.generateShadowingParagraph(from: selectedPhrases)
            let paragraph = generated.paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            shadowingPromptText = paragraph.isEmpty
                ? "In 30 to 45 seconds, describe a realistic situation using these phrases: \(selectedPhrases.joined(separator: ", "))."
                : paragraph

            let cleanRequired = generated.requiredPhrases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            shadowingRequiredPhrases = cleanRequired.isEmpty ? selectedPhrases : cleanRequired
            lastShadowingPhraseSet = Set(shadowingRequiredPhrases.map { normalizeForMatching($0) })
            shadowingTranscript = ""
            shadowingScore = 0
            shadowingFeedbackMessage = "New prompt ready. Repeat the paragraph naturally."
        } catch {
            shadowingPromptText = "In 30 to 45 seconds, describe a realistic situation using these phrases: \(selectedPhrases.joined(separator: ", "))."
            shadowingRequiredPhrases = selectedPhrases
            lastShadowingPhraseSet = Set(selectedPhrases.map { normalizeForMatching($0) })
            shadowingFeedbackMessage = "Using fallback prompt: \(error.localizedDescription)"
        }
    }

    func playShadowingPrompt() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isShadowingPromptPlaying = false
            shadowingFeedbackMessage = "Prompt playback stopped."
            return
        }

        let text = shadowingPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.48

            isShadowingPromptPlaying = true
            shadowingFeedbackMessage = "Playing prompt..."
            speechSynthesizer.speak(utterance)
        } catch {
            isShadowingPromptPlaying = false
            shadowingFeedbackMessage = "Unable to play prompt right now."
        }
    }

    func startShadowingCapture() async {
        do {
            guard !isShadowingRecording else { return }
            try await requestRequiredPermissions()
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
                isShadowingPromptPlaying = false
            }
            try await speakingPracticeAudioRecorderService.startRecording()
            isShadowingRecording = true
            shadowingTranscript = ""
            shadowingFeedbackMessage = "Listening... repeat the prompt naturally."
        } catch {
            isShadowingRecording = false
            shadowingFeedbackMessage = error.localizedDescription
        }
    }

    func stopShadowingCaptureAndEvaluate() async {
        guard isShadowingRecording else { return }

        do {
            let audioURL = try await speakingPracticeAudioRecorderService.stopRecording()
            isShadowingRecording = false
            shadowingFeedbackMessage = "Evaluating your attempt..."

            let transcript = try await voiceProcessingService.transcribePracticeAudio(at: audioURL)
            shadowingTranscript = transcript

            let evaluation = evaluateShadowingAttempt(
                transcript: transcript,
                promptText: shadowingPromptText,
                requiredPhrases: shadowingRequiredPhrases
            )

            shadowingScore = evaluation.score
            shadowingFeedbackMessage = evaluation.feedback
        } catch {
            isShadowingRecording = false
            shadowingFeedbackMessage = "Could not evaluate shadowing attempt: \(error.localizedDescription)"
        }
    }

    func generateContextSpeakingMission() async {
        let candidatePhrases = vocabularyStore.items
            .prefix(3)
            .map(\.phrase)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !candidatePhrases.isEmpty else {
            missionFeedbackMessage = "Add a few vocabulary items first to create a mission."
            return
        }

        isGeneratingSpeakingMission = true
        defer { isGeneratingSpeakingMission = false }

        do {
            let mission = try await voiceProcessingService.generateSpeakingMission(from: candidatePhrases)
            currentSpeakingMission = mission
            missionTranscript = ""
            missionCoverageCount = 0
            missionCoverageTotal = mission.requiredPhrases.count
            missionFeedbackMessage = "Mission ready. Speak for about 20–40 seconds."
        } catch {
            missionFeedbackMessage = "Could not generate mission: \(error.localizedDescription)"
        }
    }

    func generateBehavioralQuestion() async {
        isGeneratingBehavioralQuestion = true
        defer { isGeneratingBehavioralQuestion = false }

        do {
            let question = try await voiceProcessingService.generateBehavioralQuestion(category: selectedBehavioralCategory)
            currentBehavioralQuestion = question
            behavioralAnswerTranscript = ""
            behavioralEvaluation = nil
            behavioralStatusMessage = "Question ready. Answer in 45–90 seconds."
        } catch {
            behavioralStatusMessage = "Could not generate question: \(error.localizedDescription)"
        }
    }

    func startBehavioralAnswerCapture() async {
        do {
            guard !isBehavioralAnswerRecording else { return }
            guard currentBehavioralQuestion != nil else {
                behavioralStatusMessage = "Generate a behavioral question first."
                return
            }

            try await requestRequiredPermissions()
            try await behavioralAudioRecorderService.startRecording()

            isBehavioralAnswerRecording = true
            behavioralStatusMessage = "Listening... use STAR structure in your answer."
        } catch {
            isBehavioralAnswerRecording = false
            behavioralStatusMessage = error.localizedDescription
        }
    }

    func stopBehavioralAnswerCaptureAndEvaluate() async {
        guard isBehavioralAnswerRecording else { return }

        do {
            let audioURL = try await behavioralAudioRecorderService.stopRecording()
            isBehavioralAnswerRecording = false
            isEvaluatingBehavioralAnswer = true
            behavioralStatusMessage = "Evaluating your behavioral answer..."

            let transcript = try await voiceProcessingService.transcribePracticeAudio(at: audioURL)
            behavioralAnswerTranscript = transcript

            guard let question = currentBehavioralQuestion else {
                behavioralStatusMessage = "Question context missing. Please generate again."
                isEvaluatingBehavioralAnswer = false
                return
            }

            let evaluation = try await voiceProcessingService.evaluateBehavioralAnswer(
                question: question,
                answerTranscript: transcript
            )

            behavioralEvaluation = evaluation
            behavioralStatusMessage = "Evaluation complete. Review STAR gaps and refine your answer."
            isEvaluatingBehavioralAnswer = false
        } catch {
            isBehavioralAnswerRecording = false
            isEvaluatingBehavioralAnswer = false
            behavioralStatusMessage = "Could not evaluate behavioral answer: \(error.localizedDescription)"
        }
    }

    func startMissionCapture() async {
        do {
            guard !isMissionRecording else { return }
            guard currentSpeakingMission != nil else {
                missionFeedbackMessage = "Generate a mission first."
                return
            }

            try await requestRequiredPermissions()
            try await speakingPracticeAudioRecorderService.startRecording()

            isMissionRecording = true
            missionTranscript = ""
            missionFeedbackMessage = "Listening... include all required phrases."
        } catch {
            isMissionRecording = false
            missionFeedbackMessage = error.localizedDescription
        }
    }

    func stopMissionCaptureAndEvaluate() async {
        guard isMissionRecording else { return }

        do {
            let audioURL = try await speakingPracticeAudioRecorderService.stopRecording()
            isMissionRecording = false
            missionFeedbackMessage = "Evaluating mission response..."

            let transcript = try await voiceProcessingService.transcribePracticeAudio(at: audioURL)
            missionTranscript = transcript

            guard let mission = currentSpeakingMission else {
                missionFeedbackMessage = "Mission context missing. Please generate again."
                return
            }

            let evaluation = evaluateMissionAttempt(transcript: transcript, mission: mission)
            missionCoverageCount = evaluation.covered
            missionCoverageTotal = mission.requiredPhrases.count
            missionFeedbackMessage = evaluation.feedback
        } catch {
            isMissionRecording = false
            missionFeedbackMessage = "Could not evaluate mission response: \(error.localizedDescription)"
        }
    }

    func startVocabularyPractice(maxNewCardsPerDay: Int = 5) {
        let queue = vocabularyStore.buildPracticeQueue(maxNewCardsPerDay: maxNewCardsPerDay)
        vocabularyPracticeQueue = queue
        vocabularyPracticeCurrentItem = queue.first
        vocabularyPracticeSessionInitialCount = queue.count
        isVocabularyPracticeAnswerRevealed = false
        isVocabularyPracticeActive = !queue.isEmpty
        refreshVocabularyPracticeStats(maxNewCardsPerDay: maxNewCardsPerDay)
    }

    func revealCurrentVocabularyCardAnswer() {
        guard vocabularyPracticeCurrentItem != nil else { return }
        isVocabularyPracticeAnswerRevealed = true
    }

    func rateCurrentVocabularyCard(_ rating: VocabularyReviewRating, maxNewCardsPerDay: Int = 5) {
        guard let current = vocabularyPracticeCurrentItem else { return }

        do {
            _ = try vocabularyStore.markReview(id: current.id, rating: rating)
        } catch {
            vocabularyVoiceStatusMessage = "Could not save card review."
        }

        advanceVocabularyPracticeQueue(maxNewCardsPerDay: maxNewCardsPerDay)
    }

    func endVocabularyPractice(maxNewCardsPerDay: Int = 5) {
        vocabularyPracticeQueue = []
        vocabularyPracticeCurrentItem = nil
        vocabularyPracticeSessionInitialCount = 0
        isVocabularyPracticeAnswerRevealed = false
        isVocabularyPracticeActive = false
        refreshVocabularyPracticeStats(maxNewCardsPerDay: maxNewCardsPerDay)
    }

    func refreshVocabularyPracticeStats(maxNewCardsPerDay: Int = 5) {
        vocabularyPracticeReviewedToday = vocabularyStore.reviewedCount(on: Date())
        vocabularyPracticeDueCount = vocabularyStore.buildPracticeQueue(maxNewCardsPerDay: maxNewCardsPerDay).count
    }

    func vocabularySectionCounts(maxNewCardsPerDay: Int = 5, now: Date = Date()) -> (due: Int, new: Int, learning: Int, review: Int, difficult: Int) {
        let due = vocabularyStore.dueItems(now: now).count + vocabularyStore.newItems(limitPerDay: maxNewCardsPerDay, now: now).count
        let newCount = vocabularyStore.newItems(limitPerDay: Int.max, now: now).count
        let learning = vocabularyStore.learningItems().count
        let review = vocabularyStore.reviewItems().count
        let difficult = vocabularyStore.difficultItems().count
        return (due, newCount, learning, review, difficult)
    }

    private func hydrateVocabularyReminderSettings() {
        if defaults.object(forKey: Self.vocabularyReminderEnabledKey) != nil {
            vocabularyReminderEnabled = defaults.bool(forKey: Self.vocabularyReminderEnabledKey)
        }

        if defaults.object(forKey: Self.vocabularyReminderHourKey) != nil {
            vocabularyReminderHour = min(23, max(0, defaults.integer(forKey: Self.vocabularyReminderHourKey)))
        }

        if defaults.object(forKey: Self.vocabularyReminderMinuteKey) != nil {
            vocabularyReminderMinute = min(59, max(0, defaults.integer(forKey: Self.vocabularyReminderMinuteKey)))
        }
    }

    private func updateVocabularyReminderSchedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.vocabularyReminderNotificationID])

        guard vocabularyReminderEnabled else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                vocabularyVoiceStatusMessage = "Enable notifications in Settings to get vocabulary reminders."
                vocabularyReminderEnabled = false
                return
            }

            var dateComponents = DateComponents()
            dateComponents.hour = vocabularyReminderHour
            dateComponents.minute = vocabularyReminderMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = "Vocabulary practice reminder"
            content.body = "Quick review now helps you remember words longer."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.vocabularyReminderNotificationID,
                content: content,
                trigger: trigger
            )

            try await center.add(request)
        } catch {
            vocabularyVoiceStatusMessage = "Could not schedule vocabulary reminder."
        }
    }

    private func selectRandomShadowingPhrases(targetCount: Int) -> [String] {
        let uniquePhrases = Array(
            Set(
                vocabularyStore.items
                    .map(\.phrase)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )

        guard !uniquePhrases.isEmpty else { return [] }

        if uniquePhrases.count <= targetCount {
            return uniquePhrases.shuffled()
        }

        let previous = lastShadowingPhraseSet
        let freshPool = uniquePhrases.filter { !previous.contains(normalizeForMatching($0)) }

        if freshPool.count >= targetCount {
            return Array(freshPool.shuffled().prefix(targetCount))
        }

        var selected = freshPool.shuffled()
        let remainderPool = uniquePhrases
            .filter { phrase in
                !selected.contains(where: { normalizeForMatching($0) == normalizeForMatching(phrase) })
            }
            .shuffled()

        let needed = max(0, targetCount - selected.count)
        selected.append(contentsOf: remainderPool.prefix(needed))
        return Array(selected.prefix(targetCount))
    }

    private func normalizeForMatching(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet.whitespaces).inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(_ text: String) -> Set<String> {
        Set(
            normalizeForMatching(text)
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    private func evaluateShadowingAttempt(
        transcript: String,
        promptText: String,
        requiredPhrases: [String]
    ) -> (score: Int, feedback: String) {
        let normalizedTranscript = normalizeForMatching(transcript)
        let normalizedPrompt = normalizeForMatching(promptText)

        guard !normalizedTranscript.isEmpty else {
            return (0, "I couldn’t detect clear speech. Try again and speak a little louder.")
        }

        let required = requiredPhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let coveredPhrases = required.filter { phrase in
            normalizedTranscript.contains(normalizeForMatching(phrase))
        }

        let coverageRatio: Double = {
            guard !required.isEmpty else { return 0 }
            return Double(coveredPhrases.count) / Double(required.count)
        }()

        let transcriptTokens = tokenSet(normalizedTranscript)
        let promptTokens = tokenSet(normalizedPrompt)
        let overlap = transcriptTokens.intersection(promptTokens).count
        let similarity = promptTokens.isEmpty ? 0 : Double(overlap) / Double(promptTokens.count)

        let score = min(100, Int((coverageRatio * 60.0) + (similarity * 40.0)))
        let coverageText = required.isEmpty
            ? "No required phrase list provided."
            : "Used \(coveredPhrases.count)/\(required.count) required phrases."

        let missed = required.filter { !coveredPhrases.contains($0) }

        if score >= 85 {
            return (score, "\(coverageText) Excellent — very close to the paragraph with strong phrase usage.")
        }

        if score >= 65 {
            if missed.isEmpty {
                return (score, "\(coverageText) Good attempt. Keep the rhythm smoother and match wording even more closely.")
            }
            return (score, "\(coverageText) Missed: \(missed.joined(separator: ", ")).")
        }

        if missed.isEmpty {
            return (score, "\(coverageText) Nice phrase coverage. Now focus on mirroring more of the paragraph wording.")
        }

        return (score, "\(coverageText) Try again and include: \(missed.joined(separator: ", ")).")
    }

    private func evaluateMissionAttempt(transcript: String, mission: SpeakingMission) -> (covered: Int, feedback: String) {
        let normalizedTranscript = normalizeForMatching(transcript)
        if normalizedTranscript.isEmpty {
            return (0, "I couldn’t detect enough speech. Please try again.")
        }

        let required = mission.requiredPhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let coveredPhrases = required.filter { phrase in
            normalizedTranscript.contains(normalizeForMatching(phrase))
        }

        let wordCount = normalizedTranscript.split(separator: " ").count
        let fluencyHint: String
        if wordCount < 10 {
            fluencyHint = "Speak a bit longer to build fluency (aim 20+ words)."
        } else if wordCount < 20 {
            fluencyHint = "Good length. Try one more sentence for richer context."
        } else {
            fluencyHint = "Great response length and flow."
        }

        let missed = required.filter { !coveredPhrases.contains($0) }
        let coverageText = "Used \(coveredPhrases.count)/\(required.count) required phrases."

        if missed.isEmpty {
            return (coveredPhrases.count, "\(coverageText) Excellent mission completion. \(fluencyHint)")
        }

        return (
            coveredPhrases.count,
            "\(coverageText) Missed: \(missed.joined(separator: ", ")). \(fluencyHint)"
        )
    }

    private func advanceVocabularyPracticeQueue(maxNewCardsPerDay: Int = 5) {
        guard !vocabularyPracticeQueue.isEmpty else {
            vocabularyPracticeCurrentItem = nil
            vocabularyPracticeSessionInitialCount = 0
            isVocabularyPracticeAnswerRevealed = false
            isVocabularyPracticeActive = false
            refreshVocabularyPracticeStats(maxNewCardsPerDay: maxNewCardsPerDay)
            return
        }

        vocabularyPracticeQueue.removeFirst()
        vocabularyPracticeCurrentItem = vocabularyPracticeQueue.first
        isVocabularyPracticeAnswerRevealed = false
        isVocabularyPracticeActive = vocabularyPracticeCurrentItem != nil
        refreshVocabularyPracticeStats(maxNewCardsPerDay: maxNewCardsPerDay)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isShadowingPromptPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isShadowingPromptPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isShadowingPromptPlaying = false
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
    let exampleSentences: [String]
    let flashcardState: VocabularyFlashcardState
    let nextReviewAt: Date
    let lastReviewedAt: Date?
    let reviewCount: Int
    let consecutiveCorrectCount: Int
    let lapseCount: Int
    let easeFactor: Double
    let lastRating: VocabularyReviewRatingRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case sourceSessionID
        case phrase
        case tag
        case meaning
        case spokenSentence
        case correctedSentence
        case exampleSentences
        case flashcardState
        case nextReviewAt
        case lastReviewedAt
        case reviewCount
        case consecutiveCorrectCount
        case lapseCount
        case easeFactor
        case lastRating
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceSessionID: UUID,
        phrase: String,
        tag: String? = nil,
        meaning: String,
        spokenSentence: String,
        correctedSentence: String,
        exampleSentences: [String] = [],
        flashcardState: VocabularyFlashcardState = .new,
        nextReviewAt: Date = Date(),
        lastReviewedAt: Date? = nil,
        reviewCount: Int = 0,
        consecutiveCorrectCount: Int = 0,
        lapseCount: Int = 0,
        easeFactor: Double = 2.5,
        lastRating: VocabularyReviewRatingRecord? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceSessionID = sourceSessionID
        self.phrase = phrase
        self.tag = tag
        self.meaning = meaning
        self.spokenSentence = spokenSentence
        self.correctedSentence = correctedSentence
        self.exampleSentences = exampleSentences
        self.flashcardState = flashcardState
        self.nextReviewAt = nextReviewAt
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
        self.consecutiveCorrectCount = consecutiveCorrectCount
        self.lapseCount = lapseCount
        self.easeFactor = easeFactor
        self.lastRating = lastRating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceSessionID = try container.decode(UUID.self, forKey: .sourceSessionID)
        phrase = try container.decode(String.self, forKey: .phrase)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        meaning = try container.decode(String.self, forKey: .meaning)
        spokenSentence = try container.decode(String.self, forKey: .spokenSentence)
        correctedSentence = try container.decode(String.self, forKey: .correctedSentence)
        exampleSentences = try container.decodeIfPresent([String].self, forKey: .exampleSentences) ?? []
        flashcardState = try container.decodeIfPresent(VocabularyFlashcardState.self, forKey: .flashcardState) ?? .new
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt) ?? createdAt
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        consecutiveCorrectCount = try container.decodeIfPresent(Int.self, forKey: .consecutiveCorrectCount) ?? 0
        lapseCount = try container.decodeIfPresent(Int.self, forKey: .lapseCount) ?? 0
        easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor) ?? 2.5
        lastRating = try container.decodeIfPresent(VocabularyReviewRatingRecord.self, forKey: .lastRating)
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
    private let defaults = UserDefaults.standard
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

    func dueItems(now: Date = Date()) -> [VocabularyItem] {
        items
            .filter { $0.flashcardState != .new && $0.nextReviewAt <= now }
            .sorted {
                if $0.nextReviewAt != $1.nextReviewAt {
                    return $0.nextReviewAt < $1.nextReviewAt
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func newItems(limitPerDay: Int = Int.max, now: Date = Date()) -> [VocabularyItem] {
        let remainingAllowance = max(0, limitPerDay - newCardsReviewedCount(on: now))
        return items
            .filter { $0.flashcardState == .new }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(remainingAllowance)
            .map { $0 }
    }

    func learningItems() -> [VocabularyItem] {
        items
            .filter { $0.flashcardState == .learning }
            .sorted { $0.nextReviewAt < $1.nextReviewAt }
    }

    func reviewItems() -> [VocabularyItem] {
        items
            .filter { $0.flashcardState == .review }
            .sorted { $0.nextReviewAt < $1.nextReviewAt }
    }

    func difficultItems() -> [VocabularyItem] {
        items
            .filter { ($0.lapseCount >= 2) || ($0.lastRating == .again) }
            .sorted {
                if $0.lapseCount != $1.lapseCount {
                    return $0.lapseCount > $1.lapseCount
                }
                return $0.nextReviewAt < $1.nextReviewAt
            }
    }

    func buildPracticeQueue(maxNewCardsPerDay: Int = 5, now: Date = Date()) -> [VocabularyItem] {
        dueItems(now: now) + newItems(limitPerDay: maxNewCardsPerDay, now: now)
    }

    func reviewedCount(on date: Date = Date()) -> Int {
        defaults.integer(forKey: reviewedCountKey(for: date))
    }

    @discardableResult
    func markReview(id: UUID, rating: VocabularyReviewRating, now: Date = Date()) throws -> VocabularyItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }

        let existing = items[index]
        let wasNew = existing.flashcardState == .new
        let nextDate: Date
        let nextState: VocabularyFlashcardState
        let nextEaseFactor: Double
        let nextStreak: Int
        let nextLapseCount: Int
        let ratingRecord: VocabularyReviewRatingRecord

        switch rating {
        case .again:
            nextDate = Calendar.current.date(byAdding: .minute, value: 10, to: now) ?? now
            nextState = .learning
            nextEaseFactor = max(1.3, existing.easeFactor - 0.2)
            nextStreak = 0
            nextLapseCount = existing.lapseCount + 1
            ratingRecord = .again
        case .good:
            let proposedDays = max(1, Int(round(Double(max(1, existing.consecutiveCorrectCount + 1)) * existing.easeFactor / 2.0)))
            nextDate = Calendar.current.date(byAdding: .day, value: proposedDays, to: now) ?? now
            nextState = .review
            nextEaseFactor = min(3.2, existing.easeFactor + 0.05)
            nextStreak = existing.consecutiveCorrectCount + 1
            nextLapseCount = existing.lapseCount
            ratingRecord = .good
        case .easy:
            let proposedDays = max(3, Int(round(Double(max(2, existing.consecutiveCorrectCount + 2)) * (existing.easeFactor + 0.35))))
            nextDate = Calendar.current.date(byAdding: .day, value: proposedDays, to: now) ?? now
            nextState = .review
            nextEaseFactor = min(3.5, existing.easeFactor + 0.15)
            nextStreak = existing.consecutiveCorrectCount + 2
            nextLapseCount = existing.lapseCount
            ratingRecord = .easy
        }

        let updated = VocabularyItem(
            id: existing.id,
            createdAt: existing.createdAt,
            sourceSessionID: existing.sourceSessionID,
            phrase: existing.phrase,
            tag: existing.tag,
            meaning: existing.meaning,
            spokenSentence: existing.spokenSentence,
            correctedSentence: existing.correctedSentence,
            exampleSentences: existing.exampleSentences,
            flashcardState: nextState,
            nextReviewAt: nextDate,
            lastReviewedAt: now,
            reviewCount: existing.reviewCount + 1,
            consecutiveCorrectCount: nextStreak,
            lapseCount: nextLapseCount,
            easeFactor: nextEaseFactor,
            lastRating: ratingRecord
        )

        items[index] = updated

        if wasNew {
            incrementNewCardsReviewedCount(on: now)
        }
        incrementReviewedCount(on: now)

        try persistItems()
        return updated
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
        meaningOverride: String? = nil,
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
            meaning: meaningOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? meaningOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "Saved from word improvements.",
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

    func replaceAllItems(with cloudItems: [VocabularyItem]) {
        items = cloudItems.sorted { $0.createdAt > $1.createdAt }
        do {
            try persistItems()
        } catch {
            print("Failed to persist cloud vocabulary replace: \(error.localizedDescription)")
        }
    }

    func updateExamples(for id: UUID, examples: [String]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        let cleanExamples = examples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanExamples.isEmpty else { return }

        let existing = items[index]
        items[index] = VocabularyItem(
            id: existing.id,
            createdAt: existing.createdAt,
            sourceSessionID: existing.sourceSessionID,
            phrase: existing.phrase,
            tag: existing.tag,
            meaning: existing.meaning,
            spokenSentence: existing.spokenSentence,
            correctedSentence: existing.correctedSentence,
            exampleSentences: cleanExamples,
            flashcardState: existing.flashcardState,
            nextReviewAt: existing.nextReviewAt,
            lastReviewedAt: existing.lastReviewedAt,
            reviewCount: existing.reviewCount,
            consecutiveCorrectCount: existing.consecutiveCorrectCount,
            lapseCount: existing.lapseCount,
            easeFactor: existing.easeFactor,
            lastRating: existing.lastRating
        )

        do {
            try persistItems()
        } catch {
            print("Failed to persist vocabulary examples: \(error.localizedDescription)")
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

    private func dayStamp(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func newCardsReviewedKey(for date: Date) -> String {
        "vocabulary-new-reviewed-\(dayStamp(for: date))"
    }

    private func reviewedCountKey(for date: Date) -> String {
        "vocabulary-reviewed-total-\(dayStamp(for: date))"
    }

    private func newCardsReviewedCount(on date: Date) -> Int {
        defaults.integer(forKey: newCardsReviewedKey(for: date))
    }

    private func incrementNewCardsReviewedCount(on date: Date) {
        let key = newCardsReviewedKey(for: date)
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }

    private func incrementReviewedCount(on date: Date) {
        let key = reviewedCountKey(for: date)
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }
}
