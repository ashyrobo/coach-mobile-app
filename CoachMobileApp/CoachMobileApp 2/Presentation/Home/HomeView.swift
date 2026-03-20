import SwiftUI
import AVFoundation
import Combine
import UIKit

struct HomeView: View {
    @StateObject var viewModel: VoiceSessionViewModel

    var body: some View {
        TabView {
            RecordView(viewModel: viewModel)
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }

            RealtimeView(viewModel: viewModel)
                .tabItem {
                    Label("Realtime", systemImage: "waveform.and.mic")
                }

            VocabularyView(vocabularyStore: viewModel.vocabularyStore)
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed.fill")
                }

            HistoryView(historyStore: viewModel.historyStore)
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            SettingsView(viewModel: viewModel)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}

private struct RealtimeView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Speech in → Realtime API → Live text out")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Model: \(AppConfig.openAIRealtimeModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.realtimeStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.startRealtimeStreaming() }
                    } label: {
                        Label("Start", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRealtimeRunning)

                    Button {
                        viewModel.stopRealtimeStreaming()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isRealtimeRunning)
                }

                ScrollView {
                    Text(viewModel.realtimeLiveText.isEmpty ? "Live transcript will appear here..." : viewModel.realtimeLiveText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .navigationTitle("Realtime")
            .onDisappear {
                if viewModel.isRealtimeRunning {
                    viewModel.stopRealtimeStreaming()
                }
            }
        }
    }
}

private struct VocabularyView: View {
    @ObservedObject var vocabularyStore: VocabularyStore
    @State private var searchText: String = ""

    private var filteredItems: [VocabularyItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vocabularyStore.items }

        return vocabularyStore.items.filter { item in
            item.phrase.localizedCaseInsensitiveContains(query)
            || item.meaning.localizedCaseInsensitiveContains(query)
            || item.spokenSentence.localizedCaseInsensitiveContains(query)
            || item.correctedSentence.localizedCaseInsensitiveContains(query)
        }
    }

    private var wordItems: [VocabularyItem] {
        filteredItems.filter { vocabularyCategory(for: $0.phrase) == .word }
    }

    private var phraseItems: [VocabularyItem] {
        filteredItems.filter { vocabularyCategory(for: $0.phrase) == .phrase }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Vocabulary Yet" : "No Matches",
                        systemImage: "text.book.closed",
                        description: Text(
                            searchText.isEmpty
                            ? "Add words or phrases from Word Improvements and they will show up here."
                            : "Try another search term."
                        )
                    )
                } else {
                    List {
                        if !wordItems.isEmpty {
                            Section("Words") {
                                ForEach(wordItems) { item in
                                    vocabularyRow(for: item)
                                }
                                .onDelete { offsets in
                                    deleteItems(in: wordItems, at: offsets)
                                }
                            }
                        }

                        if !phraseItems.isEmpty {
                            Section("Phrases") {
                                ForEach(phraseItems) { item in
                                    vocabularyRow(for: item)
                                }
                                .onDelete { offsets in
                                    deleteItems(in: phraseItems, at: offsets)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vocabulary")
            .searchable(text: $searchText, prompt: "Search words or phrases")
        }
    }

    @ViewBuilder
    private func vocabularyRow(for item: VocabularyItem) -> some View {
        NavigationLink {
            VocabularyDetailView(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.phrase)
                        .font(.headline)
                    Spacer()
                }

                if let tag = item.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func deleteItems(in sourceItems: [VocabularyItem], at offsets: IndexSet) {
        for offset in offsets {
            guard sourceItems.indices.contains(offset) else { continue }
            vocabularyStore.deleteItem(id: sourceItems[offset].id)
        }
    }

    private func vocabularyCategory(for phrase: String) -> VocabularyCategory {
        let tokens = phrase
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return tokens.count <= 1 ? .word : .phrase
    }

    private enum VocabularyCategory {
        case word
        case phrase
    }
}

private struct VocabularyDetailView: View {
    let item: VocabularyItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.phrase)
                    .font(.title3.weight(.semibold))

                Group {
                    Text("Your Spoken Sentence")
                        .font(.headline)
                    Text(item.spokenSentence)
                }

                Group {
                    Text("Corrected Sentence")
                        .font(.headline)
                    Text(item.correctedSentence)
                }

                Text("Saved on \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Vocabulary Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryView: View {
    @ObservedObject var historyStore: SessionHistoryStore
    @State private var sessionToDelete: VoiceSession?

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.sessions.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "waveform",
                        description: Text("Process a recording and it will show up here.")
                    )
                } else {
                    List {
                        ForEach(historyStore.sessions) { session in
                            NavigationLink {
                                HistoryDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(threeWordTitle(for: session))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(session.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(session.mode.displayTitle)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                sessionToDelete = historyStore.sessions[index]
                            }
                        }
                    }
                }
            }
            .confirmationDialog("Delete this session?", item: $sessionToDelete) { session in
                Button("Delete", role: .destructive) {
                    historyStore.deleteSessionSafely(session)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the saved transcript, final text, tips, and audio recording.")
            }
        }
    }

    private func threeWordTitle(for session: VoiceSession) -> String {
        if let aiTitle = session.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !aiTitle.isEmpty {
            return aiTitle
        }

        let sourceText = !session.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? session.finalText
            : session.transcriptText

        let words = sourceText
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else {
            return "Untitled Session"
        }

        return words.prefix(3).joined(separator: " ").capitalized
    }
}

private struct HistoryDetailView: View {
    let session: VoiceSession
    @StateObject private var player = AudioPlayerController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(session.mode.displayTitle)
                        .font(.headline)
                    Spacer()
                    Text(session.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    player.togglePlayback(path: session.audioPath)
                } label: {
                    Label(player.isPlaying ? "Pause Recording" : "Play Recording", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage = player.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Group {
                    Text("Transcript")
                        .font(.headline)
                    Text(session.transcriptText)
                }

                Group {
                    Text("Final Text")
                        .font(.headline)
                    Text(session.finalText)
                }

                if !session.transcriptText.isEmpty,
                   !session.finalText.isEmpty,
                   session.mode == .rewordBetter,
                   session.transcriptText != session.finalText {
                    WordDiffHighlightView(
                        originalText: session.transcriptText,
                        improvedText: session.finalText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player.stopPlayback()
        }
    }
}

@MainActor
private final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?

    func togglePlayback(path: String) {
        if isPlaying {
            stopPlayback()
            return
        }

        let audioURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Recording file is missing."
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            isPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "Unable to play this recording."
            isPlaying = false
            player = nil
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

private struct RecordView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Mode", selection: $viewModel.selectedMode) {
                        ForEach(RewriteMode.allCases) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Transcription Method: \(viewModel.transcriptionMethod.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.isRecording || viewModel.isPaused || viewModel.recordingTime > 0 {
                        Label(
                            viewModel.isPaused
                                ? "Paused at \(formatTime(viewModel.recordingTime))"
                                : "Recording: \(formatTime(viewModel.recordingTime))",
                            systemImage: viewModel.isPaused ? "pause.circle.fill" : "record.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(viewModel.isPaused ? .orange : .red)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await viewModel.startRecording() }
                        } label: {
                            Label("Record", systemImage: "record.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(viewModel.isRecording || viewModel.isPaused)

                        Button {
                            Task {
                                if viewModel.isPaused {
                                    await viewModel.resumeRecording()
                                } else {
                                    await viewModel.pauseRecording()
                                }
                            }
                        } label: {
                            Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRecording && !viewModel.isPaused)

                        Button {
                            Task { await viewModel.stopRecording() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRecording && !viewModel.isPaused)
                    }

                    Button("Process Session") {
                        Task { await viewModel.processCurrentSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.latestAudioURL == nil || viewModel.isRecording || viewModel.isPaused)

                    if !viewModel.transcript.isEmpty || !viewModel.finalText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !viewModel.transcript.isEmpty {
                                Text("Transcript")
                                    .font(.headline)
                                Text(viewModel.transcript)
                            }

                            if !viewModel.finalText.isEmpty {
                                Text("Final Text")
                                    .font(.headline)
                                Text(viewModel.finalText)
                            }

                            if !viewModel.transcript.isEmpty,
                               !viewModel.finalText.isEmpty,
                               viewModel.lastProcessedMode == .rewordBetter,
                               viewModel.transcript != viewModel.finalText {
                                WordDiffHighlightView(
                                    originalText: viewModel.transcript,
                                    improvedText: viewModel.finalText,
                                    onAddToVocabulary: { phrase in
                                        viewModel.addVocabularyFromWordImprovement(phrase)
                                    }
                                )
                            }

                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel

    private let billingURL = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcription Method")
                    .font(.headline)

                Picker("Transcription Method", selection: $viewModel.transcriptionMethod) {
                    ForEach(TranscriptionMethod.allCases) { method in
                        Text(method.displayTitle).tag(method)
                    }
                }
                .pickerStyle(.menu)

                Link(destination: billingURL) {
                    Label("Open Billing Dashboard", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
        }
    }
}

private struct WordDiffHighlightView: View {
    let originalText: String
    let improvedText: String
    var onAddToVocabulary: ((String) -> VocabularyStore.ManualAddOutcome)? = nil

    @State private var lastAddedPhrase: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Word Improvements")
                .font(.headline)

            highlightedDiffText
                .font(.subheadline)

            if let onAddToVocabulary, !manualVocabularyCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add to Vocabulary")
                        .font(.subheadline.weight(.semibold))

                    ForEach(manualVocabularyCandidates, id: \.self) { phrase in
                        Button {
                            let outcome = onAddToVocabulary(phrase)
                            if outcome == .added {
                                lastAddedPhrase = phrase
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: lastAddedPhrase == phrase ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .foregroundStyle(lastAddedPhrase == phrase ? .green : .blue)
                                Text(phrase)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Label("Original/Replaced", systemImage: "minus.circle.fill")
                    .foregroundStyle(.red)
                Label("Better Alternative", systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightedDiffText: Text {
        let segments = diffSegments(original: originalText, improved: improvedText)

        return segments.enumerated().reduce(Text("")) { partial, element in
            let (index, segment) = element
            let prefix = index == 0 ? "" : " "

            var piece = Text(prefix + segment.text)
            switch segment.kind {
            case .unchanged:
                piece = piece.foregroundColor(.primary)
            case .removed:
                piece = piece
                    .foregroundColor(.red)
                    .strikethrough(true, color: .red)
            case .added:
                piece = piece.foregroundColor(.green)
            }

            return partial + piece
        }
    }

    private var manualVocabularyCandidates: [String] {
        let addedSegments = diffSegments(original: originalText, improved: improvedText)
            .filter { $0.kind == .added }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var orderedUnique: [String] = []

        for phrase in addedSegments {
            let key = phrase.lowercased()
            if seen.insert(key).inserted {
                orderedUnique.append(phrase)
            }
        }

        return orderedUnique
    }

    private func diffSegments(original: String, improved: String) -> [DiffSegment] {
        let originalWords = tokenize(original)
        let improvedWords = tokenize(improved)

        let n = originalWords.count
        let m = improvedWords.count

        guard n > 0 || m > 0 else { return [] }

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if originalWords[i - 1].caseInsensitiveCompare(improvedWords[j - 1]) == .orderedSame {
                        lcs[i][j] = lcs[i - 1][j - 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                    }
                }
            }
        }

        var i = n
        var j = m
        var rawSegments: [DiffSegment] = []

        while i > 0 && j > 0 {
            if originalWords[i - 1].caseInsensitiveCompare(improvedWords[j - 1]) == .orderedSame {
                rawSegments.append(.init(text: improvedWords[j - 1], kind: .unchanged))
                i -= 1
                j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                rawSegments.append(.init(text: originalWords[i - 1], kind: .removed))
                i -= 1
            } else {
                rawSegments.append(.init(text: improvedWords[j - 1], kind: .added))
                j -= 1
            }
        }

        while i > 0 {
            rawSegments.append(.init(text: originalWords[i - 1], kind: .removed))
            i -= 1
        }

        while j > 0 {
            rawSegments.append(.init(text: improvedWords[j - 1], kind: .added))
            j -= 1
        }

        let orderedSegments = rawSegments.reversed()
        return mergeConsecutiveSegments(Array(orderedSegments))
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
    }

    private func mergeConsecutiveSegments(_ segments: [DiffSegment]) -> [DiffSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [DiffSegment] = []
        merged.reserveCapacity(segments.count)

        for segment in segments {
            guard !segment.text.isEmpty else { continue }

            if var last = merged.last, last.kind == segment.kind {
                last.text += " \(segment.text)"
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }

        return merged
    }
}

private struct DiffSegment {
    var text: String
    let kind: DiffKind
}

private enum DiffKind {
    case unchanged
    case removed
    case added
}

private extension View {
    func confirmationDialog<Item: Identifiable>(
        _ title: LocalizedStringKey,
        item: Binding<Item?>,
        @ViewBuilder actions: (Item) -> some View,
        @ViewBuilder message: (Item) -> some View
    ) -> some View {
        confirmationDialog(title, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    item.wrappedValue = nil
                }
            }
        )) {
            if let currentItem = item.wrappedValue {
                actions(currentItem)
            }
        } message: {
            if let currentItem = item.wrappedValue {
                message(currentItem)
            }
        }
    }
}
