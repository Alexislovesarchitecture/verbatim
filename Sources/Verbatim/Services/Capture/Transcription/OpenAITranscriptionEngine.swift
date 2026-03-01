import Foundation

final class OpenAITranscriptionEngine: TranscriptionEngineProtocol {
    private struct OpenAIResponse: Decodable { let text: String }
    private struct OpenAIErrorResponse: Decodable {
        let error: OpenAIAPIError?
        let detail: String?
    }

    private struct OpenAIAPIError: Decodable {
        let message: String
        let type: String?
        let code: String?
    }

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini-transcribe") {
        self.apiKey = apiKey
        self.model = model
    }

    private let maxUploadBytes = 25 * 1024 * 1024

    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionEngineError.missingAPIKey
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= maxUploadBytes else {
            throw TranscriptionEngineError.requestFailed("Audio file is larger than 25MB. Split or compress the recording before upload.")
        }

        print("OpenAI transcription request start: model=\(model), language=\(language), fileSize=\(fileSize), fileName=\(fileURL.lastPathComponent)")

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(fileURL: fileURL, boundary: boundary, prompt: prompt, language: language)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionEngineError.requestFailed("Invalid HTTP response from OpenAI")
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = parseErrorMessage(from: data)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown OpenAI error"
            throw TranscriptionEngineError.requestFailed("HTTP \(http.statusCode): \(message)")
        }

        do {
            let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return parsed.text
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "Non-text payload"
            throw TranscriptionEngineError.requestFailed("Invalid OpenAI response: \(error.localizedDescription). Payload: \(payload)")
        }
    }

    private func multipartBody(fileURL: URL, boundary: String, prompt: String?, language: String) throws -> Data {
        let audio = try Data(contentsOf: fileURL)
        var output = Data()

        func field(_ key: String, _ value: String) {
            output.append("--\(boundary)\r\n".data(using: .utf8)!)
            output.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            output.append("\(value)\r\n".data(using: .utf8)!)
        }

        field("model", model)
        field("response_format", "json")
        field("language", language)
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }

        output.append("--\(boundary)\r\n".data(using: .utf8)!)
        output.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        output.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        output.append(audio)
        output.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return output
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard
            let payload = String(data: data, encoding: .utf8),
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
        else {
            return nil
        }

        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: trimmed) {
            if let message = decoded.error?.message {
                return message
            }
            return decoded.detail
        }

        return nil
    }
}
