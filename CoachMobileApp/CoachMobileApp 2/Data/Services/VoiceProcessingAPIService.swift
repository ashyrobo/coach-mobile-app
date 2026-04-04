import Foundation

final class VoiceProcessingAPIService: VoiceProcessingServicing {
    private struct VocabularyCloudPayload: Codable {
        let updatedAt: String?
        let items: [VocabularyItem]
    }

    private struct SpeakingMissionRequest: Codable {
        let phrases: [String]
    }

    private struct SpeakingMissionResponse: Codable {
        let mission: SpeakingMission
    }

    private struct BehavioralQuestionRequest: Codable {
        let category: BehavioralQuestionCategory
    }

    private struct BehavioralQuestionResponse: Codable {
        let question: BehavioralQuestion
    }

    private struct BehavioralEvaluationRequest: Codable {
        let question: BehavioralQuestion
        let answerTranscript: String

        enum CodingKeys: String, CodingKey {
            case question
            case answerTranscript = "answer_transcript"
        }
    }

    private struct BehavioralEvaluationResponse: Codable {
        let evaluation: BehavioralEvaluation
    }

    func processAudio(at audioURL: URL, mode: RewriteMode, tone: RewriteTone?) async throws -> RewriteResult {
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
            tone: tone?.rawValue,
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

    func transcribePracticeAudio(at audioURL: URL) async throws -> String {
        let extraction = try await extractVocabularyFromAudio(at: audioURL)
        return extraction.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func generateSpeakingMission(from phrases: [String]) async throws -> SpeakingMission {
        var request = URLRequest(url: AppConfig.speakingMissionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanPhrases = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        request.httpBody = try JSONEncoder().encode(SpeakingMissionRequest(phrases: cleanPhrases))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let payload = try JSONDecoder().decode(SpeakingMissionResponse.self, from: data)
            return payload.mission
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func generateBehavioralQuestion(category: BehavioralQuestionCategory) async throws -> BehavioralQuestion {
        var request = URLRequest(url: AppConfig.behavioralQuestionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(BehavioralQuestionRequest(category: category))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let payload = try JSONDecoder().decode(BehavioralQuestionResponse.self, from: data)
            return payload.question
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func evaluateBehavioralAnswer(question: BehavioralQuestion, answerTranscript: String) async throws -> BehavioralEvaluation {
        var request = URLRequest(url: AppConfig.behavioralEvaluationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanAnswer = answerTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpBody = try JSONEncoder().encode(
            BehavioralEvaluationRequest(question: question, answerTranscript: cleanAnswer)
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let payload = try JSONDecoder().decode(BehavioralEvaluationResponse.self, from: data)
            return payload.evaluation
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func fetchCloudVocabulary() async throws -> [VocabularyItem] {
        var request = URLRequest(url: AppConfig.vocabularyCloudURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let payload = try JSONDecoder().decode(VocabularyCloudPayload.self, from: data)
            return payload.items
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func replaceCloudVocabulary(with items: [VocabularyItem]) async throws {
        var request = URLRequest(url: AppConfig.vocabularyCloudURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(VocabularyCloudPayload(updatedAt: nil, items: items))

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }
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
        tone: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        body.append("\(mode)\r\n")

        if let tone, !tone.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"tone\"\r\n\r\n")
            body.append("\(tone)\r\n")
        }

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
