import SwiftUI
import AVFoundation
import Combine

struct HomeView: View {
    @StateObject var viewModel: VoiceSessionViewModel

    var body: some View {
        TabView {
            RecordView(viewModel: viewModel)
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
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
                                        Text(session.mode.displayTitle)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(session.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(session.transcriptText)
                                        .lineLimit(2)
                                        .font(.subheadline)
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
            .navigationTitle("History")
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

                if !session.coachingTips.isEmpty {
                    Text("Coaching Tips")
                        .font(.headline)
                    ForEach(session.coachingTips, id: \.self) { tip in
                        Text("• \(tip)")
                    }
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

                    if !viewModel.isOnDeviceTranscriptionAvailable {
                        Label("On-device live transcription is currently unavailable for this locale/device state.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

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

                    if viewModel.isRecording || viewModel.isPaused || !viewModel.liveTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Transcript")
                                .font(.headline)

                            if viewModel.liveTranscript.isEmpty {
                                Text("Listening…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(viewModel.liveTranscript)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

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

                            if !viewModel.tips.isEmpty {
                                Text("Coaching Tips")
                                    .font(.headline)
                                ForEach(viewModel.tips, id: \.self) { tip in
                                    Text("• \(tip)")
                                }
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
                Text("OpenAI Credit")
                    .font(.headline)

                Text(viewModel.openAICreditDisplay)
                    .font(.title3.weight(.semibold))

                Button {
                    Task { await viewModel.refreshOpenAICredit() }
                } label: {
                    if viewModel.isLoadingCredit {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Refresh Credit", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)

                Divider()

                Text("OpenAI Usage (Month to Date)")
                    .font(.headline)

                Text(viewModel.openAIMonthlyUsageDisplay)
                    .font(.title3.weight(.semibold))

                Button {
                    Task { await viewModel.refreshOpenAIMonthlyUsage() }
                } label: {
                    if viewModel.isLoadingUsage {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Refresh Usage", systemImage: "chart.bar.xaxis")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)

                Link(destination: billingURL) {
                    Label("Open Billing Dashboard", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Note: API billing/usage endpoints may be restricted by OpenAI account type, org role, or key scope.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .task {
                if viewModel.openAICreditDisplay == "Not loaded" {
                    await viewModel.refreshOpenAICredit()
                }
                if viewModel.openAIMonthlyUsageDisplay == "Not loaded" {
                    await viewModel.refreshOpenAIMonthlyUsage()
                }
            }
        }
    }
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
