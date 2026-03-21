import Foundation
import AVFoundation

final class VoiceProcessingAPIService: VoiceProcessingServicing {
    func processAudio(at audioURL: URL, mode: RewriteMode) async throws -> RewriteResult {
        let endpoint = AppConfig.voiceProcessingBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("process-audio")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        request.httpBody = makeMultipartBody(
            audioData: audioData,
            audioFileName: audioURL.lastPathComponent,
            mode: mode.rawValue,
            boundary: boundary
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }
            return try JSONDecoder().decode(RewriteResult.self, from: data)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func extractVocabularyFromAudio(at audioURL: URL) async throws -> VocabularyExtractionResult {
        var request = URLRequest(url: AppConfig.vocabularyExtractURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        request.httpBody = makeVocabularyMultipartBody(
            audioData: audioData,
            audioFileName: audioURL.lastPathComponent,
            boundary: boundary
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }
            return try JSONDecoder().decode(VocabularyExtractionResult.self, from: data)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func generateVocabularyExamples(for phrase: String) async throws -> [String] {
        var request = URLRequest(url: AppConfig.vocabularyExamplesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["phrase": phrase])

        struct VocabularyExamplesResponse: Codable {
            let examples: [String]
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let payload = try JSONDecoder().decode(VocabularyExamplesResponse.self, from: data)
            return payload.examples.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    private func makeMultipartBody(
        audioData: Data,
        audioFileName: String,
        mode: String,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        body.append("\(mode)\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audioFileName)\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func makeVocabularyMultipartBody(
        audioData: Data,
        audioFileName: String,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audioFileName)\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}

final class OpenAIRealtimeStreamingService {
    enum RealtimeEvent {
        case textDelta(String)
        case status(String)
        case error(String)
    }

    private let audioEngine = AVAudioEngine()
    private let sendQueue = DispatchQueue(label: "OpenAIRealtimeStreamingService.send")
    private var webSocketTask: URLSessionWebSocketTask?
    private var isRunning = false
    private var onEvent: ((RealtimeEvent) -> Void)?

    func start(onEvent: @escaping (RealtimeEvent) -> Void) async throws {
        guard !isRunning else { return }

        self.onEvent = onEvent
        try await bootstrapRealtimeSession()
        try configureAndStartAudioSession()
        try connectWebSocket()

        isRunning = true
        self.onEvent?(.status("Realtime connected"))
        receiveLoop()
        sendSessionUpdate()
    }

    func stop() {
        guard isRunning else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isRunning = false
        onEvent?(.status("Realtime stopped"))
    }

    private func bootstrapRealtimeSession() async throws {
        var components = URLComponents(url: AppConfig.realtimeSessionURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "model", value: AppConfig.openAIRealtimeModel)
        ]

        guard let url = components?.url else {
            throw AppError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.invalidResponse
        }
    }

    private func connectWebSocket() throws {
        webSocketTask = URLSession.shared.webSocketTask(with: AppConfig.realtimeWebSocketURL)
        webSocketTask?.resume()
    }

    private func configureAndStartAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(24_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }
            guard let audioData = Self.makePCM16MonoData(from: buffer), !audioData.isEmpty else { return }
            self.sendAudioChunk(audioData)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func sendSessionUpdate() {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-mini-transcribe"
                ],
                "turn_detection": [
                    "type": "server_vad"
                ]
            ]
        ]

        sendJSON(payload)
    }

    private func sendAudioChunk(_ data: Data) {
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        sendQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            guard let webSocketTask = self.webSocketTask else { return }

            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: data, encoding: .utf8) else {
                return
            }

            webSocketTask.send(.string(text)) { [weak self] error in
                if let error {
                    self?.onEvent?(.error("Realtime send failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func receiveLoop() {
        guard let webSocketTask else { return }

        webSocketTask.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .failure(error):
                self.onEvent?(.error("Realtime receive failed: \(error.localizedDescription)"))
                self.stop()
            case let .success(message):
                switch message {
                case let .string(text):
                    self.handleIncomingTextEvent(text)
                case .data:
                    break
                @unknown default:
                    break
                }

                if self.isRunning {
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleIncomingTextEvent(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }

        if type == "relay.error", let message = payload["message"] as? String {
            onEvent?(.error(message))
            return
        }

        if let delta = Self.extractDeltaText(from: payload), !delta.isEmpty {
            onEvent?(.textDelta(delta))
            return
        }

        if type == "relay.ready" {
            onEvent?(.status("Realtime relay ready"))
        }
    }

    private static func extractDeltaText(from payload: [String: Any]) -> String? {
        let type = payload["type"] as? String

        if type == "response.text.delta" || type == "response.output_text.delta" {
            return payload["delta"] as? String
        }

        if type == "conversation.item.input_audio_transcription.delta" {
            return payload["delta"] as? String
        }

        if type == "response.audio_transcript.delta" {
            return payload["delta"] as? String
        }

        return nil
    }

    private static func makePCM16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var pcmData = Data(count: frameLength * MemoryLayout<Int16>.size)

        if buffer.format.commonFormat == .pcmFormatInt16,
           let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)

            pcmData.withUnsafeMutableBytes { rawBuffer in
                guard let output = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
                for frame in 0..<frameLength {
                    var mixed: Int32 = 0
                    for channel in 0..<channelCount {
                        mixed += Int32(channels[channel][frame])
                    }
                    output[frame] = Int16(mixed / Int32(max(1, channelCount)))
                }
            }

            return pcmData
        }

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)

        pcmData.withUnsafeMutableBytes { rawBuffer in
            guard let output = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            for frame in 0..<frameLength {
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channels[channel][frame]
                }

                sample /= Float(max(1, channelCount))
                sample = min(1, max(-1, sample))
                output[frame] = Int16(sample * Float(Int16.max))
            }
        }

        return pcmData
    }
}
