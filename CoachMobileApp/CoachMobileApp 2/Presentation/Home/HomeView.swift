import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: VoiceSessionViewModel

    var body: some View {
        NavigationStack {
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

                Button(action: {
                    Task { await viewModel.toggleRecording() }
                }) {
                    Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isRecording ? Color.red : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("Process Session") {
                    Task { await viewModel.processCurrentSession() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.latestAudioURL == nil || viewModel.isRecording)

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

                Spacer()
            }
            .padding()
            .navigationTitle("Coach")
        }
    }
}
