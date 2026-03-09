import Foundation
import WhisperKit

enum WhisperKitManagedHelperRunner {
    static func runIfNeeded(arguments: [String]) -> Bool {
        guard arguments.dropFirst().first == "--whisperkit-helper" else {
            return false
        }

        let helperArguments = Array(arguments.dropFirst(2))
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = EXIT_SUCCESS

        Task {
            defer { semaphore.signal() }
            do {
                let output = try await run(arguments: helperArguments)
                FileHandle.standardOutput.write(output)
            } catch {
                let message = error.localizedDescription + "\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
                exitCode = EXIT_FAILURE
            }
        }

        semaphore.wait()
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) async throws -> Data {
        guard let command = arguments.first else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing WhisperKit helper command.")
        }

        switch command {
        case "health":
            return try JSONEncoder().encode(
                ManagedWhisperKitHelperResponse(
                    success: true,
                    message: "Managed WhisperKit helper is ready.",
                    transcript: nil
                )
            )
        case "transcribe":
            let payload = try await transcribe(arguments: Array(arguments.dropFirst()))
            return try JSONEncoder().encode(payload)
        default:
            throw LocalTranscriptionError.whisperTranscriptionFailed("Unknown WhisperKit helper command: \(command)")
        }
    }

    private static func transcribe(arguments: [String]) async throws -> ManagedWhisperKitHelperResponse {
        let parsed = try parse(arguments: arguments)
        let config = WhisperKitConfig(
            model: parsed.modelName,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: nil,
            download: true,
            useBackgroundDownloadSession: false
        )
        let pipe = try await WhisperKit(config)
        let results = try await pipe.transcribe(
            audioPath: parsed.audioPath,
            decodeOptions: DecodingOptions(verbose: false, withoutTimestamps: false, wordTimestamps: true)
        )

        let segments = results
            .flatMap { $0.segments }
            .map {
                TranscriptSegment(
                    start: TimeInterval($0.start),
                    end: TimeInterval($0.end),
                    speaker: nil,
                    text: $0.text
                )
            }
        let rawText = results
            .map { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let transcript = Transcript(
            rawText: rawText,
            segments: segments,
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: parsed.modelName,
            responseFormat: "text"
        )
        return ManagedWhisperKitHelperResponse(success: true, message: nil, transcript: transcript)
    }

    private static func parse(arguments: [String]) throws -> (audioPath: String, modelName: String) {
        var audioPath: String?
        var modelName: String?
        var iterator = arguments.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--audio-path":
                audioPath = iterator.next()
            case "--model":
                modelName = iterator.next()
            default:
                continue
            }
        }

        guard let audioPath, !audioPath.isEmpty else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing --audio-path for WhisperKit helper.")
        }
        guard let modelName, !modelName.isEmpty else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing --model for WhisperKit helper.")
        }

        return (audioPath, modelName)
    }
}
