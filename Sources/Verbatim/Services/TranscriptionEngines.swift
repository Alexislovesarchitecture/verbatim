import Foundation

protocol TranscriptionEngine {
    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String
}

enum TranscriptionEngineError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case missingExecutable
    case executableNotRunnable
    case missingModelPath
    case missingModelFile
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key."
        case .invalidResponse:
            return "Transcription service returned an invalid response."
        case .missingExecutable:
            return "whisper-cli was not found at the configured path."
        case .executableNotRunnable:
            return "whisper-cli exists but is not executable. Check file permissions."
        case .missingModelPath:
            return "Missing whisper.cpp model path."
        case .missingModelFile:
            return "whisper.cpp model file was not found at the configured path."
        case .processFailed(let output):
            return "Local transcription failed: \(output)"
        }
    }
}

final class OpenAITranscriptionEngine: TranscriptionEngine {
    private struct ResponseBody: Decodable {
        let text: String
    }

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String) {
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
            throw TranscriptionEngineError.processFailed(String(data: data, encoding: .utf8) ?? "Unknown server error")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.text
    }

    private func multipartBody(fileURL: URL, boundary: String, prompt: String?, language: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        var data = Data()

        func appendField(name: String, value: String) {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "json")
        appendField(name: "language", value: language)
        if let prompt, !prompt.isEmpty {
            appendField(name: "prompt", value: prompt)
        }

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return data
    }
}

final class WhisperCLITranscriptionEngine: TranscriptionEngine {
    private let executablePath: String
    private let modelPath: String

    init(executablePath: String, modelPath: String) {
        self.executablePath = executablePath
        self.modelPath = modelPath
    }

    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String {
        let resolvedExecutablePath = (executablePath as NSString).expandingTildeInPath
        let executableURL = URL(fileURLWithPath: resolvedExecutablePath)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw TranscriptionEngineError.missingExecutable
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw TranscriptionEngineError.executableNotRunnable
        }

        let resolvedModelPath = (modelPath as NSString).expandingTildeInPath
        guard !resolvedModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionEngineError.missingModelPath
        }
        guard FileManager.default.fileExists(atPath: resolvedModelPath) else {
            throw TranscriptionEngineError.missingModelFile
        }

        let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-m", resolvedModelPath,
            "-f", fileURL.path,
            "-l", language,
            "-otxt",
            "-of", outputBase.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let combinedData = pipe.fileHandleForReading.readDataToEndOfFile()
        let combinedOutput = String(data: combinedData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let output = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = output.isEmpty ? "whisper-cli exited with status \(process.terminationStatus)." : output
            throw TranscriptionEngineError.processFailed(summary)
        }

        let outputURL = outputBase.appendingPathExtension("txt")
        guard let text = try? String(contentsOf: outputURL), !text.isEmpty else {
            throw TranscriptionEngineError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
