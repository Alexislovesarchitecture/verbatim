import Foundation

final class OpenAITranscriptionEngine: TranscriptionEngineProtocol {
    private struct OpenAIResponse: Decodable { let text: String }

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini-transcribe") {
        self.apiKey = apiKey
        self.model = model
    }

    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionEngineError.missingAPIKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(fileURL: fileURL, boundary: boundary, prompt: prompt, language: language)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriptionEngineError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return parsed.text
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
}
