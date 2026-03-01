import Foundation

final class WhisperCppTranscriptionEngine: TranscriptionEngineProtocol {
    private let cliPath: String
    private let modelPath: String

    init(cliPath: String, modelPath: String) {
        self.cliPath = cliPath
        self.modelPath = modelPath
    }

    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String {
        let executable = (cliPath as NSString).expandingTildeInPath
        let model = (modelPath as NSString).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: executable) else {
            throw TranscriptionEngineError.missingExecutable
        }
        guard fm.isExecutableFile(atPath: executable) else {
            throw TranscriptionEngineError.executableNotRunnable
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionEngineError.missingModel
        }
        guard fm.fileExists(atPath: model) else {
            throw TranscriptionEngineError.missingModel
        }

        let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-m", model, "-f", fileURL.path, "-l", language, "-otxt", "-of", outputBase.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let combined = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw TranscriptionEngineError.requestFailed(combined.isEmpty ? "whisper.cpp exited with \(process.terminationStatus)" : combined)
        }

        let textURL = outputBase.appendingPathExtension("txt")
        let text = try String(contentsOf: textURL, encoding: .utf8)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
