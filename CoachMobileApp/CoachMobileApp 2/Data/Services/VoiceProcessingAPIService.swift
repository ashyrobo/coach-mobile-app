import Foundation

final class VoiceProcessingAPIService: VoiceProcessingServicing {
    private struct VocabularyCloudPayload: Codable {
        let updatedAt: String?
        let items: [VocabularyItem]
    }

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
