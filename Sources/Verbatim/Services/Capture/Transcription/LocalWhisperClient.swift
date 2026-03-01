import Foundation

struct LocalWhisperServerResponse: Decodable {
    let text: String?
    let transcription: [LocalWhisperServerSegment]?
}

struct LocalWhisperServerSegment: Decodable {
    let text: String?
}

enum LocalWhisperClientError: Error {
    case unsupportedPayload
    case blankAudio
}

final class LocalWhisperClient {
    func transcribe(fileURL: URL, prompt: String?, language: String, serverURL: URL) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.httpBody = try multipartBody(fileURL: fileURL, boundary: boundary, prompt: prompt, language: language)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionEngineError.requestFailed("Invalid HTTP response from local whisper server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? "unknown"
            throw TranscriptionEngineError.requestFailed("Local server returned \(http.statusCode): \(payload)")
        }

        let parsed = try parseResponse(data)
        if isBlankAudio(rawText: parsed) {
            throw TranscriptionEngineError.emptyTranscript
        }
        return parsed
    }

    private func multipartBody(fileURL: URL, boundary: String, prompt: String?, language: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        var output = Data()

        func textPart(_ key: String, _ value: String) {
            output.append("--\(boundary)\r\n".data(using: .utf8)!)
            output.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            output.append("\(value)\r\n".data(using: .utf8)!)
        }

        textPart("response_format", "json")
        textPart("language", language)
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textPart("prompt", prompt)
        }

        output.append("--\(boundary)\r\n".data(using: .utf8)!)
        output.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        output.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        output.append(fileData)
        output.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        return output
    }

    func parseResponse(_ data: Data) throws -> String {
        guard let raw = String(data: data, encoding: .utf8),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionEngineError.invalidResponse
        }

        do {
            return try parsePayload(data)
        } catch LocalWhisperClientError.blankAudio {
            throw TranscriptionEngineError.emptyTranscript
        } catch {
            throw TranscriptionEngineError.invalidResponse
        }
    }

    private func parsePayload(_ data: Data) throws -> String {
        if let decoded = try? JSONDecoder().decode(LocalWhisperServerResponse.self, from: data) {
            if let text = decoded.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let normalized = normalizeText(text)
                if !isBlankAudio(rawText: normalized) { return normalized }
                throw LocalWhisperClientError.blankAudio
            }

            if let segments = decoded.transcription {
                let all = segments.compactMap { $0.text }.joined(separator: " ")
                let normalized = normalizeText(all)
                if !normalized.isEmpty && !isBlankAudio(rawText: normalized) {
                    return normalized
                }
                if !normalized.isEmpty {
                    throw LocalWhisperClientError.blankAudio
                }
            }
        }

        if let value = try? JSONDecoder().decode(String.self, from: data) {
            let normalized = normalizeText(value)
            if !normalized.isEmpty && !isBlankAudio(rawText: normalized) {
                return normalized
            }
            if !normalized.isEmpty {
                throw LocalWhisperClientError.blankAudio
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String {
                let normalized = normalizeText(text)
                if !normalized.isEmpty && !isBlankAudio(rawText: normalized) {
                    return normalized
                }
                if !normalized.isEmpty {
                    throw LocalWhisperClientError.blankAudio
                }
            }
            if let transcription = json["transcription"] as? [String] {
                let normalized = normalizeText(transcription.joined(separator: " "))
                if !normalized.isEmpty && !isBlankAudio(rawText: normalized) {
                    return normalized
                }
                if !normalized.isEmpty {
                    throw LocalWhisperClientError.blankAudio
                }
            }
            if let result = json["result"] as? String {
                let normalized = normalizeText(result)
                if !normalized.isEmpty && !isBlankAudio(rawText: normalized) {
                    return normalized
                }
                if !normalized.isEmpty {
                    throw LocalWhisperClientError.blankAudio
                }
            }
        }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw LocalWhisperClientError.unsupportedPayload
        }
        let normalized = normalizeText(raw)
        if isBlankAudio(rawText: normalized) {
            throw LocalWhisperClientError.blankAudio
        }
        if !normalized.isEmpty {
            return normalized
        }

        throw LocalWhisperClientError.unsupportedPayload
    }

    private func normalizeText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isBlankAudio(rawText: String) -> Bool {
        let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "[blank_audio]" || normalized == "[blank audio]"
    }
}
