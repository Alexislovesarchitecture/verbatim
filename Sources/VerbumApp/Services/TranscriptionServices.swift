import Foundation

final class MockTranscriptionService: TranscriptionServicing {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let filename = request.audioURL.lastPathComponent
        return TranscriptionResult(rawText: "Mock transcript from \(filename). new paragraph Verbum is ready.", engine: .mock)
    }
}

final class OpenAITranscriptionService: TranscriptionServicing {
    private let apiKeyProvider: () -> String
    private let modelProvider: () -> String

    init(apiKeyProvider: @escaping () -> String, modelProvider: @escaping () -> String) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let apiKey = apiKeyProvider().trimmed()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Verbum.OpenAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key."])
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: request.audioURL)
        let body = try MultipartFormBuilder.build(boundary: boundary) { form in
            form.addField(name: "model", value: modelProvider())
            form.addField(name: "language", value: request.languageCode)
            if !request.customTerms.isEmpty {
                form.addField(name: "prompt", value: request.customTerms.joined(separator: ", "))
            }
            form.addFile(name: "file", filename: request.audioURL.lastPathComponent, mimeType: "audio/mp4", data: audioData)
        }

        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Verbum.OpenAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response."])
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown OpenAI error"
            throw NSError(domain: "Verbum.OpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return TranscriptionResult(rawText: decoded.text, engine: .openAI)
    }

    private struct OpenAITranscriptionResponse: Decodable {
        let text: String
    }
}

final class WhisperCPPTranscriptionService: TranscriptionServicing {
    private let binaryPathProvider: () -> String
    private let modelPathProvider: () -> String

    init(binaryPathProvider: @escaping () -> String, modelPathProvider: @escaping () -> String) {
        self.binaryPathProvider = binaryPathProvider
        self.modelPathProvider = modelPathProvider
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let binaryPath = binaryPathProvider().trimmed()
        let modelPath = modelPathProvider().trimmed()

        guard !binaryPath.isEmpty, !modelPath.isEmpty else {
            throw NSError(domain: "Verbum.WhisperCPP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set both whisper binary path and model path in Settings."])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        process.arguments = [
            "-m", modelPath,
            "-f", request.audioURL.path,
            "-l", request.languageCode,
            "-nt",
            "-of", outputBase.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "whisper.cpp failed"
            throw NSError(domain: "Verbum.WhisperCPP", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }

        let textURL = outputBase.appendingPathExtension("txt")
        let text = try String(contentsOf: textURL).trimmed()
        return TranscriptionResult(rawText: text, engine: .whisperCPP)
    }
}

struct MultipartFormBuilder {
    final class Form {
        fileprivate var parts: [Data] = []
        private let boundary: String

        init(boundary: String) {
            self.boundary = boundary
        }

        func addField(name: String, value: String) {
            var data = Data()
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
            parts.append(data)
        }

        func addFile(name: String, filename: String, mimeType: String, data fileData: Data) {
            var data = Data()
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            data.append(fileData)
            data.append("\r\n".data(using: .utf8)!)
            parts.append(data)
        }

        fileprivate func build() -> Data {
            var result = Data()
            parts.forEach { result.append($0) }
            result.append("--\(boundary)--\r\n".data(using: .utf8)!)
            return result
        }
    }

    static func build(boundary: String, configure: (Form) throws -> Void) throws -> Data {
        let form = Form(boundary: boundary)
        try configure(form)
        return form.build()
    }
}
