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

            VocabularyView(viewModel: viewModel)
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed.fill")
                }

            PracticeView(viewModel: viewModel)
                .tabItem {
                    Label("Practice", systemImage: "figure.mind.and.body")
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

private struct PracticeView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    behavioralInterviewSection
                    shadowingSection
                    speakingMissionSection
                }
                .padding()
            }
            .navigationTitle("Practice")
        }
    }

    @ViewBuilder
    private var behavioralInterviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Behavioral Interview", systemImage: "person.2.wave.2")
                .font(.headline)

            Picker("Category", selection: $viewModel.selectedBehavioralCategory) {
                ForEach(BehavioralQuestionCategory.allCases) { category in
                    Text(category.displayTitle).tag(category)
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { await viewModel.generateBehavioralQuestion() }
            } label: {
                Label(
                    viewModel.isGeneratingBehavioralQuestion ? "Generating..." : "Generate Behavioral Question",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGeneratingBehavioralQuestion)

            if let question = viewModel.currentBehavioralQuestion {
                Text(question.prompt)
                    .font(.subheadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !question.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Focus: \(question.focus)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        if viewModel.isBehavioralAnswerRecording {
                            await viewModel.stopBehavioralAnswerCaptureAndEvaluate()
                        } else {
                            await viewModel.startBehavioralAnswerCapture()
                        }
                    }
                } label: {
                    Label(
                        viewModel.isBehavioralAnswerRecording ? "Stop Answer" : "Start Answer",
                        systemImage: viewModel.isBehavioralAnswerRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isBehavioralAnswerRecording ? .red : .purple)
                .disabled(viewModel.isEvaluatingBehavioralAnswer)
            }

            if !viewModel.behavioralStatusMessage.isEmpty {
                Text(viewModel.behavioralStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.behavioralAnswerTranscript.isEmpty {
                Text("You said: \(viewModel.behavioralAnswerTranscript)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let evaluation = viewModel.behavioralEvaluation {
                VStack(alignment: .leading, spacing: 8) {
                    Text(evaluation.summaryFeedback)
                        .font(.subheadline)

                    Text(
                        "STAR: S \(evaluation.starCoverage.situation ? "✅" : "❌")  T \(evaluation.starCoverage.task ? "✅" : "❌")  A \(evaluation.starCoverage.action ? "✅" : "❌")  R \(evaluation.starCoverage.result ? "✅" : "❌")"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text(
                        "Scores — Clarity \(evaluation.rubric.clarity)/5 • Ownership \(evaluation.rubric.ownership)/5 • Specificity \(evaluation.rubric.specificity)/5 • Impact \(evaluation.rubric.impact)/5 • Conciseness \(evaluation.rubric.conciseness)/5"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !evaluation.improvedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Improved Answer")
                            .font(.subheadline.weight(.semibold))
                        Text(evaluation.improvedAnswer)
                            .font(.subheadline)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if !evaluation.followUpQuestions.isEmpty {
                        Text("Follow-up Questions")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(evaluation.followUpQuestions.enumerated()), id: \.offset) { index, followUp in
                                Text("\(index + 1). \(followUp)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var shadowingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Shadowing Practice", systemImage: "waveform.and.mic")
                .font(.headline)

            if let item = viewModel.shadowingItem {
                Text("Target phrase: \(item.phrase)")
                    .font(.subheadline.weight(.semibold))

                Text(viewModel.shadowingPromptText)
                    .font(.subheadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        viewModel.playShadowingPrompt()
                    } label: {
                        Label("Play Prompt", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            if viewModel.isShadowingRecording {
                                await viewModel.stopShadowingCaptureAndEvaluate()
                            } else {
                                await viewModel.startShadowingCapture()
                            }
                        }
                    } label: {
                        Label(viewModel.isShadowingRecording ? "Stop" : "Speak", systemImage: viewModel.isShadowingRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isShadowingRecording ? .red : .blue)

                    Button {
                        viewModel.cycleShadowingItem()
                    } label: {
                        Label("Next", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if !viewModel.shadowingTranscript.isEmpty {
                    Text("You said: \(viewModel.shadowingTranscript)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.shadowingFeedbackMessage.isEmpty {
                    Text("Score: \(viewModel.shadowingScore)/100 • \(viewModel.shadowingFeedbackMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Add vocabulary items first to start shadowing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            viewModel.refreshShadowingCandidate()
        }
    }

    @ViewBuilder
    private var speakingMissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Context Speaking Mission", systemImage: "target")
                .font(.headline)

            Button {
                Task { await viewModel.generateContextSpeakingMission() }
            } label: {
                Label(viewModel.isGeneratingSpeakingMission ? "Generating..." : "Generate Mission", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGeneratingSpeakingMission)

            if let mission = viewModel.currentSpeakingMission {
                Text(mission.prompt)
                    .font(.subheadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !mission.requiredPhrases.isEmpty {
                    Text("Required: \(mission.requiredPhrases.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            if viewModel.isMissionRecording {
                                await viewModel.stopMissionCaptureAndEvaluate()
                            } else {
                                await viewModel.startMissionCapture()
                            }
                        }
                    } label: {
                        Label(viewModel.isMissionRecording ? "Stop Mission" : "Start Mission", systemImage: viewModel.isMissionRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isMissionRecording ? .red : .green)
                }

                if !viewModel.missionTranscript.isEmpty {
                    Text("You said: \(viewModel.missionTranscript)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.missionFeedbackMessage.isEmpty {
                    Text("Coverage: \(viewModel.missionCoverageCount)/\(viewModel.missionCoverageTotal) • \(viewModel.missionFeedbackMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(viewModel.missionFeedbackMessage.isEmpty ? "Generate a mission to practice multiple phrases in one response." : viewModel.missionFeedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VocabularyView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel
    private let practiceMaxNewCardsPerDay = 5
    private let recencyCalendar = Calendar.current
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var vocabularyStore: VocabularyStore { viewModel.vocabularyStore }

    private var wordItems: [VocabularyItem] {
        vocabularyStore.items.filter { vocabularyCategory(for: $0.phrase) == .word }
    }

    private var phraseItems: [VocabularyItem] {
        vocabularyStore.items.filter { vocabularyCategory(for: $0.phrase) == .phrase }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Label("Due: \(viewModel.vocabularyPracticeDueCount)", systemImage: "calendar.badge.clock")
                        Label("Reviewed today: \(viewModel.vocabularyPracticeReviewedToday)", systemImage: "checkmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    vocabularyStatusLegend
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                if viewModel.isVocabularyPracticeActive {
                    vocabularyPracticeView
                } else {
                    Group {
                        if vocabularyStore.items.isEmpty {
                            ContentUnavailableView(
                                "No Vocabulary Yet",
                                systemImage: "text.book.closed",
                                description: Text(
                                    "Add words or phrases from Word Improvements and they will show up here."
                                )
                            )
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    if !wordItems.isEmpty {
                                        wordGridSection(items: wordItems)
                                    }

                                    if !phraseItems.isEmpty {
                                        phraseListSection(items: phraseItems)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.refreshVocabularyPracticeStats(maxNewCardsPerDay: practiceMaxNewCardsPerDay)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            if viewModel.isVocabularyPracticeActive {
                                viewModel.endVocabularyPractice(maxNewCardsPerDay: practiceMaxNewCardsPerDay)
                            } else {
                                viewModel.startVocabularyPractice(maxNewCardsPerDay: practiceMaxNewCardsPerDay)
                            }
                        } label: {
                            Label(
                                viewModel.isVocabularyPracticeActive ? "End Practice" : "Start Practice",
                                systemImage: viewModel.isVocabularyPracticeActive ? "xmark.circle.fill" : "play.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(vocabularyStore.items.isEmpty)

                        Button {
                            Task {
                                if viewModel.isVocabularyVoiceRecording {
                                    await viewModel.stopVocabularyVoiceCaptureAndSave()
                                } else {
                                    await viewModel.startVocabularyVoiceCapture()
                                }
                            }
                        } label: {
                            Label(
                                viewModel.isVocabularyVoiceRecording ? "Stop Voice" : "Voice Add",
                                systemImage: viewModel.isVocabularyVoiceRecording ? "stop.circle.fill" : "mic.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.isVocabularyVoiceRecording ? .red : .blue)
                        .accessibilityLabel(viewModel.isVocabularyVoiceRecording ? "Stop voice add" : "Start voice add")
                    }
                    .padding(.horizontal)

                    if !viewModel.vocabularyVoiceStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(viewModel.vocabularyVoiceStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }

    @ViewBuilder
    private func vocabularyRow(for item: VocabularyItem) -> some View {
        if vocabularyCategory(for: item.phrase) == .word {
            wordTile(for: item)
        } else {
            phraseRow(for: item)
        }
    }

    @ViewBuilder
    private func wordTile(for item: VocabularyItem) -> some View {
        let style = styleForVocabularyItem(item)

        NavigationLink {
            VocabularyDetailView(viewModel: viewModel, item: item)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(style.baseColor)
                    .frame(width: 8, height: 8)

                Text(item.phrase)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text(style.recencyLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.baseColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(style.baseColor.opacity(0.14))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteVocabularyItem(id: item.id, maxNewCardsPerDay: practiceMaxNewCardsPerDay)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func phraseRow(for item: VocabularyItem) -> some View {
        let style = styleForVocabularyItem(item)

        NavigationLink {
            VocabularyDetailView(viewModel: viewModel, item: item)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(style.baseColor)
                    .frame(width: 8, height: 8)

                Text(item.phrase)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                if let tag = item.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Text(style.recencyLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.baseColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(style.baseColor.opacity(0.14))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteVocabularyItem(id: item.id, maxNewCardsPerDay: practiceMaxNewCardsPerDay)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var vocabularyPracticeView: some View {
        if let current = viewModel.vocabularyPracticeCurrentItem {
            VStack(alignment: .leading, spacing: 14) {
                Text("Flashcard Practice")
                    .font(.headline)

                Text(current.phrase)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if viewModel.isVocabularyPracticeAnswerRevealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meaning")
                            .font(.subheadline.weight(.semibold))
                        Text(current.meaning)
                            .font(.subheadline)

                        Text("Example")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                        Text(current.correctedSentence)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        Button("Again") {
                            viewModel.rateCurrentVocabularyCard(.again, maxNewCardsPerDay: practiceMaxNewCardsPerDay)
                        }
                        .buttonStyle(.bordered)

                        Button("Good") {
                            viewModel.rateCurrentVocabularyCard(.good, maxNewCardsPerDay: practiceMaxNewCardsPerDay)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Easy") {
                            viewModel.rateCurrentVocabularyCard(.easy, maxNewCardsPerDay: practiceMaxNewCardsPerDay)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Show Answer") {
                        viewModel.revealCurrentVocabularyCardAnswer()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Remaining cards: \(viewModel.vocabularyPracticeQueue.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        } else {
            ContentUnavailableView(
                "No Cards Due",
                systemImage: "checkmark.circle",
                description: Text("You’re done for now. Great job.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func wordGridSection(items: [VocabularyItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    wordTile(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func phraseListSection(items: [VocabularyItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phrases")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    phraseRow(for: item)
                }
            }
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

    private struct VocabularyCardVisualStyle {
        let baseColor: Color
        let backgroundColor: Color
        let borderColor: Color
        let recencyLabel: String
    }

    @ViewBuilder
    private var vocabularyStatusLegend: some View {
        HStack(spacing: 10) {
            legendPill(color: .orange, text: "Learning")
            legendPill(color: .green, text: "Stable")
            legendPill(color: .gray, text: "New/Stale")
        }
        .font(.caption2)
    }

    @ViewBuilder
    private func legendPill(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }

    private func styleForVocabularyItem(_ item: VocabularyItem) -> VocabularyCardVisualStyle {
        let baseColor: Color
        switch item.flashcardState {
        case .new:
            baseColor = .gray
        case .learning:
            baseColor = .orange
        case .review:
            baseColor = .green
        }

        let recencyLabel = recencyLabel(for: item)
        let recencyOpacity = recencyStrength(for: item)

        return VocabularyCardVisualStyle(
            baseColor: baseColor,
            backgroundColor: baseColor.opacity(recencyOpacity),
            borderColor: baseColor.opacity(0.38),
            recencyLabel: recencyLabel
        )
    }

    private func recencyStrength(for item: VocabularyItem, now: Date = Date()) -> Double {
        guard let lastReviewedAt = item.lastReviewedAt else { return 0.08 }

        let days = recencyCalendar.dateComponents([.day], from: lastReviewedAt, to: now).day ?? 99
        switch days {
        case ..<1:
            return 0.25
        case 1...7:
            return 0.16
        default:
            return 0.10
        }
    }

    private func recencyLabel(for item: VocabularyItem, now: Date = Date()) -> String {
        guard let lastReviewedAt = item.lastReviewedAt else {
            return item.flashcardState == .new ? "new" : "stale"
        }

        let days = recencyCalendar.dateComponents([.day], from: lastReviewedAt, to: now).day ?? 99
        switch days {
        case ..<1:
            return "today"
        case 1...7:
            return "this week"
        default:
            return "stale"
        }
    }
}

private struct VocabularyDetailView: View {
    @ObservedObject var viewModel: VoiceSessionViewModel
    let item: VocabularyItem

    private var examples: [String] {
        viewModel.vocabularyExamples(for: item)
    }

    private var isLoadingExamples: Bool {
        viewModel.vocabularyExamplesLoadingID == item.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if let tag = item.tag, !tag.isEmpty {
                        Text(tag.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(item.phrase)
                        .font(.title2.weight(.bold))

                    Text("Saved on \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                vocabularyInfoCard(
                    title: "Meaning",
                    icon: "book.closed.fill",
                    accentColor: .indigo,
                    content: item.meaning
                )

                vocabularyInfoCard(
                    title: "Your Spoken Sentence",
                    icon: "mic.fill",
                    accentColor: .orange,
                    content: item.spokenSentence
                )

                vocabularyInfoCard(
                    title: "Corrected Sentence",
                    icon: "checkmark.seal.fill",
                    accentColor: .green,
                    content: item.correctedSentence
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("Use Cases", systemImage: "text.badge.star")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    if isLoadingExamples {
                        ProgressView("Generating examples...")
                    } else if examples.isEmpty {
                        Text("Examples will be generated automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(examples.enumerated()), id: \.offset) { index, sentence in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.purple)
                                        .frame(width: 18, height: 18)
                                        .background(Color.purple.opacity(0.12))
                                        .clipShape(Circle())

                                    Text(sentence)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Vocabulary Item")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            await viewModel.loadVocabularyExamples(for: item)
        }
    }

    @ViewBuilder
    private func vocabularyInfoCard(
        title: String,
        icon: String,
        accentColor: Color,
        content: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(accentColor)

            Text(content)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                    if viewModel.selectedMode == .rewordBetter {
                        HStack {
                            Text("Tone")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Picker("Tone", selection: $viewModel.selectedRewriteTone) {
                                ForEach(RewriteTone.allCases) { tone in
                                    Text(tone.displayTitle).tag(tone)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Processing Path: \(viewModel.transcriptionMethod.displayTitle)")
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
