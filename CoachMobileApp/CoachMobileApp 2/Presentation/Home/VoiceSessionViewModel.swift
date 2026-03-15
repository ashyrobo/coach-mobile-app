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
    @Published var liveTranscript: String = ""
    @Published var isOnDeviceTranscriptionAvailable = false
    @Published var openAICreditDisplay: String = "Not loaded"
    @Published var openAIMonthlyUsageDisplay: String = "Not loaded"
    @Published var isLoadingCredit = false
    @Published var isLoadingUsage = false
    @Published var selectedMode: RewriteMode = .summarize
    @Published var statusMessage: String = "Ready to record"
    @Published var transcript: String = ""
    @Published var finalText: String = ""
    @Published var tips: [String] = []
    @Published var latestAudioURL: URL?

    let historyStore: SessionHistoryStore

    private let permissionService: PermissionServicing
    private let audioRecorderService: AudioRecorderServicing
    private let processVoiceSessionUseCase: ProcessVoiceSessionUseCase
    private var recordingState: RecordingState = .idle
    private var recordingTimerCancellable: AnyCancellable?
    private var finalizedLiveTranscript: String = ""
    private var currentPartialLiveTranscript: String = ""

    init(
        historyStore: SessionHistoryStore,
        permissionService: PermissionServicing,
        audioRecorderService: AudioRecorderServicing,
        voiceProcessingService: VoiceProcessingServicing
    ) {
        self.historyStore = historyStore
        self.permissionService = permissionService
        self.audioRecorderService = audioRecorderService
        self.processVoiceSessionUseCase = ProcessVoiceSessionUseCase(voiceProcessingService: voiceProcessingService)
        configureLiveTranscription()
    }

    convenience init() {
        self.init(
            historyStore: SessionHistoryStore(),
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
            liveTranscript = ""
            finalizedLiveTranscript = ""
            currentPartialLiveTranscript = ""
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
            finalizeCurrentPartialSegmentIfNeeded()

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
            finalizeCurrentPartialSegmentIfNeeded()
            recordingTime = audioRecorderService.currentRecordingTime()
            if !finalizedLiveTranscript.isEmpty {
                transcript = finalizedLiveTranscript
            } else if !liveTranscript.isEmpty {
                transcript = liveTranscript
            }
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
            statusMessage = "Done"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshOpenAICredit() async {
        isLoadingCredit = true
        defer { isLoadingCredit = false }

        let endpoint = AppConfig.voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("openai-credit")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                openAICreditDisplay = "Unavailable"
                return
            }

            let payload = try JSONDecoder().decode(OpenAICreditPayload.self, from: data)
            if let remainingUSD = payload.remainingUSD {
                openAICreditDisplay = String(format: "$%.2f remaining", remainingUSD)
            } else {
                openAICreditDisplay = payload.message ?? "Unavailable"
            }
        } catch {
            openAICreditDisplay = "Unavailable"
        }
    }

    func refreshOpenAIMonthlyUsage() async {
        isLoadingUsage = true
        defer { isLoadingUsage = false }

        let endpoint = AppConfig.voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("openai-usage-month")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                openAIMonthlyUsageDisplay = "Unavailable"
                return
            }

            let payload = try JSONDecoder().decode(OpenAIMonthlyUsagePayload.self, from: data)
            if let monthToDateUSD = payload.monthToDateUSD {
                openAIMonthlyUsageDisplay = String(format: "$%.2f this month", monthToDateUSD)
            } else {
                openAIMonthlyUsageDisplay = payload.message ?? "Unavailable"
            }
        } catch {
            openAIMonthlyUsageDisplay = "Unavailable"
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

    private func configureLiveTranscription() {
        audioRecorderService.setLiveTranscriptionHandler { [weak self] update in
            guard let self else { return }
            let incomingText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if update.isFinal {
                self.finalizedLiveTranscript = self.mergeTranscript(
                    self.finalizedLiveTranscript,
                    with: incomingText
                )
                self.currentPartialLiveTranscript = ""
            } else {
                let previousPartial = self.currentPartialLiveTranscript
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Speech framework may re-segment after long pauses and emit a fresh partial
                // that doesn't include prior words. Promote the previous partial first so text
                // doesn't visually disappear.
                if !previousPartial.isEmpty,
                   !incomingText.isEmpty,
                   !incomingText.hasPrefix(previousPartial),
                   !previousPartial.hasPrefix(incomingText) {
                    self.finalizedLiveTranscript = self.mergeTranscript(
                        self.finalizedLiveTranscript,
                        with: previousPartial
                    )
                }

                // Ignore empty partial updates so previously shown content remains visible.
                if !incomingText.isEmpty {
                    self.currentPartialLiveTranscript = incomingText
                }
            }

            self.liveTranscript = self.composeLiveTranscript()
        }

        audioRecorderService.setLiveTranscriptionAvailabilityHandler { [weak self] isAvailable in
            self?.isOnDeviceTranscriptionAvailable = isAvailable
        }
    }

    private func composeLiveTranscript() -> String {
        [
            finalizedLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
            currentPartialLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func mergeTranscript(_ existing: String, with incoming: String) -> String {
        let cleanExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanIncoming.isEmpty else { return cleanExisting }
        guard !cleanExisting.isEmpty else { return cleanIncoming }

        let canonicalExisting = canonicalizedForComparison(cleanExisting)
        let canonicalIncoming = canonicalizedForComparison(cleanIncoming)

        if canonicalExisting == canonicalIncoming {
            return cleanExisting
        }

        if canonicalExisting.contains(canonicalIncoming) {
            return cleanExisting
        }

        if canonicalIncoming.contains(canonicalExisting) {
            return cleanIncoming
        }

        if cleanIncoming.hasPrefix(cleanExisting) {
            return cleanIncoming
        }

        if cleanExisting.hasSuffix(cleanIncoming) {
            return cleanExisting
        }

        let overlap = overlapLengthBetweenSuffixAndPrefix(existing: cleanExisting, incoming: cleanIncoming)
        if overlap > 0 {
            let remainder = String(cleanIncoming.dropFirst(overlap))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if remainder.isEmpty {
                return cleanExisting
            }

            return "\(cleanExisting) \(remainder)"
        }

        return "\(cleanExisting) \(cleanIncoming)"
    }

    private func canonicalizedForComparison(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func overlapLengthBetweenSuffixAndPrefix(existing: String, incoming: String) -> Int {
        let maxOverlap = min(existing.count, incoming.count)
        guard maxOverlap > 0 else { return 0 }

        for length in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = String(existing.suffix(length)).lowercased()
            let prefix = String(incoming.prefix(length)).lowercased()
            if suffix == prefix {
                return length
            }
        }

        return 0
    }

    private func finalizeCurrentPartialSegmentIfNeeded() {
        let partial = currentPartialLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }

        finalizedLiveTranscript = mergeTranscript(finalizedLiveTranscript, with: partial)
        currentPartialLiveTranscript = ""
        liveTranscript = composeLiveTranscript()
    }
}

private struct OpenAICreditPayload: Decodable {
    let remainingUSD: Double?
    let message: String?
}

private struct OpenAIMonthlyUsagePayload: Decodable {
    let monthToDateUSD: Double?
    let message: String?
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

