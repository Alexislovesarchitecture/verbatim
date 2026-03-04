import Foundation

@available(macOS 26.0, *)
@available(iOS 26.0, *)
protocol TranscriptionServiceProtocol {
    func transcribe(audioFileURL: URL, apiKey: String?, modelID: String) async throws -> String
}

enum OpenAITranscriptionError: LocalizedError {
    case missingApiKey
    case missingAudioFile
    case requestFailed(Error)
    case invalidResponse
    case emptyTranscription
    case serverError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Set OPENAI_API_KEY in your environment."
        case .missingAudioFile:
            return "Recorded audio file is missing."
        case .requestFailed(let error):
            return "Transcription request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Transcription API returned an invalid response."
        case .emptyTranscription:
            return "No text was returned from transcription."
        case .serverError(let status, let message):
            return "OpenAI API error (\(status)): \(message)"
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class OpenAITranscriptionService: TranscriptionServiceProtocol {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(audioFileURL: URL, apiKey: String?, modelID: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw OpenAITranscriptionError.missingAudioFile
        }

        let providedApiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalApiKey = providedApiKey?.isEmpty == false ? providedApiKey : envApiKey, !finalApiKey.isEmpty else {
            throw OpenAITranscriptionError.missingApiKey
        }

        let audioData = try Data(contentsOf: audioFileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(finalApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(audioData: audioData, boundary: boundary, modelID: modelID)

        let (responseData, response) = try await performRequestWithRetry(request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = parseServerErrorMessage(from: responseData)
            throw OpenAITranscriptionError.serverError(status: http.statusCode, message: message)
        }

        if let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: responseData) {
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw OpenAITranscriptionError.emptyTranscription
            }
            return trimmed
        }

        let fallback = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !fallback.isEmpty else {
            throw OpenAITranscriptionError.emptyTranscription
        }
        return fallback
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 1...2 {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                guard attempt < 2, shouldRetry(for: error) else {
                    break
                }
            }
        }

        throw OpenAITranscriptionError.requestFailed(lastError ?? URLError(.unknown))
    }

    private func shouldRetry(for error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func parseServerErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
           let message = decoded.error.message,
           !message.isEmpty {
            return message
        }

        let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bodyText.isEmpty ? "No response body" : bodyText
    }

    private func makeMultipartBody(audioData: Data, boundary: String, modelID: String) -> Data {
        var body = Data()

        appendFormDataHeader(name: "file", filename: "audio.wav", mimeType: "audio/wav", boundary: boundary, into: &body)
        body.append(audioData)
        append(&body, "\r\n")

        appendFormField(name: "model", value: modelID, boundary: boundary, into: &body)
        appendFormField(name: "response_format", value: "json", boundary: boundary, into: &body)

        append(&body, "--\(boundary)--\r\n")
        return body
    }

    private func appendFormDataHeader(name: String, filename: String, mimeType: String, boundary: String, into body: inout Data) {
        append(&body, "--\(boundary)\r\n")
        append(&body, "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append(&body, "Content-Type: \(mimeType)\r\n\r\n")
    }

    private func appendFormField(name: String, value: String, boundary: String, into body: inout Data) {
        append(&body, "--\(boundary)\r\n")
        append(&body, "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(&body, "\(value)\r\n")
    }

    private func append(_ body: inout Data, _ string: String) {
        body.append(Data(string.utf8))
    }
}
