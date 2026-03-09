import Foundation
import WhisperKit

struct LocalTranscriptionRouteResolution: Equatable, Sendable {
    let configuredMode: LocalTranscriptionEngineMode
    let resolvedBackend: LocalTranscriptionBackend
    let selectedModel: LocalTranscriptionModel
    let serverConnectionMode: WhisperKitServerConnectionMode?
    let lifecycleState: String?
    let message: String?
    let usedLegacyFallback: Bool
}

actor LocalTranscriptionRouteTracker {
    private var latestResolution: LocalTranscriptionRouteResolution?

    func record(_ resolution: LocalTranscriptionRouteResolution) {
        latestResolution = resolution
    }

    func latest() -> LocalTranscriptionRouteResolution? {
        latestResolution
    }
}

struct WhisperKitServerStatus: Equatable, Sendable {
    let isReachable: Bool
    let message: String
    let activeModel: String?

    static let idle = WhisperKitServerStatus(
        isReachable: false,
        message: "WhisperKit server not checked yet.",
        activeModel: nil
    )
}

struct WhisperKitDownloadManifestEntry: Equatable, Sendable {
    let model: LocalTranscriptionModel
    let variantName: String
    let approximateSizeLabel: String
    let qualityNote: String
}

actor WhisperKitModelManager {
    typealias RuntimeStatusProvider = @Sendable () -> WhisperRuntimeStatus

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let manifest: [LocalTranscriptionModel: WhisperKitDownloadManifestEntry]
    private let runtimeStatusProvider: RuntimeStatusProvider
    private var installStates: [LocalTranscriptionModel: WhisperModelInstallState] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        manifest: [LocalTranscriptionModel: WhisperKitDownloadManifestEntry]? = nil,
        runtimeStatusProvider: RuntimeStatusProvider? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = WhisperKitModelManager.makeRootDirectoryURL(
            fileManager: fileManager,
            baseDirectoryURL: baseDirectoryURL
        )
        self.manifest = manifest ?? Self.defaultManifest
        self.runtimeStatusProvider = runtimeStatusProvider ?? { Self.defaultRuntimeStatus() }
    }

    func runtimeStatus() -> WhisperRuntimeStatus {
        runtimeStatusProvider()
    }

    func refreshInstallStates() -> [LocalTranscriptionModel: WhisperModelInstallState] {
        for model in LocalTranscriptionModel.allCases where model.isWhisperModel {
            installStates[model] = resolvedInstallState(for: model)
        }
        return installStates
    }

    func installState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        let state = resolvedInstallState(for: model)
        installStates[model] = state
        return state
    }

    func refreshModelState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        installState(for: model)
    }

    func installedModelURL(for model: LocalTranscriptionModel) -> URL? {
        guard case .ready(let url) = installState(for: model) else {
            return nil
        }
        return url
    }

    func downloadModel(
        _ model: LocalTranscriptionModel,
        progress: (@Sendable (Double?) async -> Void)? = nil
    ) async -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) does not use a WhisperKit model.")
            installStates[model] = failedState
            return failedState
        }

        let runtime = runtimeStatus()
        guard runtime.isSupported else {
            let failedState = WhisperModelInstallState.failed(message: runtime.message)
            installStates[model] = failedState
            return failedState
        }

        installStates[model] = .downloading(progress: nil)
        await progress?(nil)

        do {
            try ensureDirectoriesExist()
            let downloadedURL = try await WhisperKit.download(
                variant: entry.variantName,
                downloadBase: stagedDownloadsDirectoryURL,
                useBackgroundSession: false
            ) { currentProgress in
                Task {
                    let fraction = currentProgress.totalUnitCount > 0
                        ? Double(currentProgress.completedUnitCount) / Double(currentProgress.totalUnitCount)
                        : nil
                    await progress?(fraction)
                }
            }

            let destinationURL = stagedModelDirectoryURL(for: model)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: downloadedURL, to: destinationURL)
            try validateModelDirectory(at: destinationURL, entry: entry, locationDescription: "Downloaded WhisperKit model")
            let state = WhisperModelInstallState.downloaded(stagedURL: destinationURL)
            installStates[model] = state
            await progress?(1.0)
            return state
        } catch {
            let failedState = WhisperModelInstallState.failed(message: "Download failed: \(error.localizedDescription)")
            installStates[model] = failedState
            return failedState
        }
    }

    func installModel(
        _ model: LocalTranscriptionModel,
        progress: (@Sendable (Double?) async -> Void)? = nil
    ) async -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) does not use a WhisperKit model.")
            installStates[model] = failedState
            return failedState
        }

        let runtime = runtimeStatus()
        guard runtime.isSupported else {
            let failedState = WhisperModelInstallState.failed(message: runtime.message)
            installStates[model] = failedState
            return failedState
        }

        let stagedURL = stagedModelDirectoryURL(for: model)
        guard fileManager.fileExists(atPath: stagedURL.path) else {
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) must be downloaded before it can be installed.")
            installStates[model] = failedState
            return failedState
        }

        installStates[model] = .installing
        await progress?(nil)

        do {
            try ensureDirectoriesExist()
            try validateModelDirectory(at: stagedURL, entry: entry, locationDescription: "Downloaded WhisperKit model")
            let destinationURL = installedModelDirectoryURL(for: model)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
            try validateModelDirectory(at: destinationURL, entry: entry, locationDescription: "Installed WhisperKit model")
            let state = WhisperModelInstallState.ready(installedURL: destinationURL)
            installStates[model] = state
            await progress?(1.0)
            return state
        } catch {
            let failedState = WhisperModelInstallState.failed(message: "Install failed: \(error.localizedDescription)")
            installStates[model] = failedState
            return failedState
        }
    }

    func removeModel(_ model: LocalTranscriptionModel) throws {
        let stagedURL = stagedModelDirectoryURL(for: model)
        if fileManager.fileExists(atPath: stagedURL.path) {
            try fileManager.removeItem(at: stagedURL)
        }
        let installedURL = installedModelDirectoryURL(for: model)
        if fileManager.fileExists(atPath: installedURL.path) {
            try fileManager.removeItem(at: installedURL)
        }
        installStates[model] = .notDownloaded
    }

    func modelsDirectoryURL() -> URL {
        installedModelsDirectoryURL
    }

    private func resolvedInstallState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            return .notDownloaded
        }

        let installedURL = installedModelDirectoryURL(for: model)
        if fileManager.fileExists(atPath: installedURL.path) {
            do {
                try validateModelDirectory(at: installedURL, entry: entry, locationDescription: "Installed WhisperKit model")
                return .ready(installedURL: installedURL)
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }

        let stagedURL = stagedModelDirectoryURL(for: model)
        if fileManager.fileExists(atPath: stagedURL.path) {
            do {
                try validateModelDirectory(at: stagedURL, entry: entry, locationDescription: "Downloaded WhisperKit model")
                return .downloaded(stagedURL: stagedURL)
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }

        return .notDownloaded
    }

    private var stagedDownloadsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
    }

    private var installedModelsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("models", isDirectory: true)
    }

    private func stagedModelDirectoryURL(for model: LocalTranscriptionModel) -> URL {
        let folderName = "openai_whisper-\(manifest[model]?.variantName ?? model.whisperKitModelName ?? model.rawValue)"
        return stagedDownloadsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    private func installedModelDirectoryURL(for model: LocalTranscriptionModel) -> URL {
        let folderName = "openai_whisper-\(manifest[model]?.variantName ?? model.whisperKitModelName ?? model.rawValue)"
        return installedModelsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: stagedDownloadsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installedModelsDirectoryURL, withIntermediateDirectories: true)
    }

    private func validateModelDirectory(
        at url: URL,
        entry: WhisperKitDownloadManifestEntry,
        locationDescription: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("\(locationDescription) for \(entry.model.title) is missing.")
        }

        let contents = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var regularFileCount = 0
        var hasEncoder = false
        var hasDecoder = false
        var hasMel = false

        while let item = contents?.nextObject() as? URL {
            regularFileCount += 1
            let name = item.lastPathComponent.lowercased()
            hasEncoder = hasEncoder || name.contains("audioencoder")
            hasDecoder = hasDecoder || name.contains("textdecoder")
            hasMel = hasMel || name.contains("melspectrogram")
        }

        guard regularFileCount > 0, hasEncoder, hasDecoder, hasMel else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("\(locationDescription) for \(entry.model.title) is incomplete. Retry the download.")
        }
    }

    private static func makeRootDirectoryURL(fileManager: FileManager, baseDirectoryURL: URL?) -> URL {
        if let baseDirectoryURL {
            return baseDirectoryURL.appendingPathComponent("WhisperKit", isDirectory: true)
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
            .appendingPathComponent("WhisperKit", isDirectory: true)
    }

    private static func defaultRuntimeStatus() -> WhisperRuntimeStatus {
        #if arch(arm64)
        return WhisperRuntimeStatus(
            isSupported: true,
            message: "WhisperKit is available on this Mac."
        )
        #else
        return WhisperRuntimeStatus(
            isSupported: false,
            message: "WhisperKit currently requires Apple Silicon."
        )
        #endif
    }

    private static let defaultManifest: [LocalTranscriptionModel: WhisperKitDownloadManifestEntry] = [
        .whisperTiny: WhisperKitDownloadManifestEntry(model: .whisperTiny, variantName: "tiny", approximateSizeLabel: "74 MB", qualityNote: "Fastest, lowest accuracy"),
        .whisperBase: WhisperKitDownloadManifestEntry(model: .whisperBase, variantName: "base", approximateSizeLabel: "141 MB", qualityNote: "Recommended balance"),
        .whisperSmall: WhisperKitDownloadManifestEntry(model: .whisperSmall, variantName: "small", approximateSizeLabel: "465 MB", qualityNote: "Better accuracy, slower"),
        .whisperMedium: WhisperKitDownloadManifestEntry(model: .whisperMedium, variantName: "medium", approximateSizeLabel: "1.43 GB", qualityNote: "High accuracy, heavy"),
        .whisperLargeV3: WhisperKitDownloadManifestEntry(model: .whisperLargeV3, variantName: "large-v3", approximateSizeLabel: "2.88 GB", qualityNote: "Best quality, largest download"),
    ]
}

final class WhisperKitLocalTranscriptionService: LocalTranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = LocalTranscriptionBackend.whisperKitSDK.engineID
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: false,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: true,
        supportsPrompt: false
    )

    private let modelManager: WhisperKitModelManager
    private let routeTracker: LocalTranscriptionRouteTracker?

    init(
        modelManager: WhisperKitModelManager,
        routeTracker: LocalTranscriptionRouteTracker? = nil
    ) {
        self.modelManager = modelManager
        self.routeTracker = routeTracker
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let selectedModel = LocalTranscriptionModel(rawValue: options.modelID) ?? .whisperBase
        return try await transcribe(audioFileURL: audioURL, model: selectedModel, options: options)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        try await transcribe(audioFileURL: audioFileURL, model: model, options: TranscriptionOptions(modelID: model.rawValue, responseFormat: "text"))
    }

    private func transcribe(
        audioFileURL: URL,
        model: LocalTranscriptionModel,
        options: TranscriptionOptions
    ) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }
        guard model.isWhisperModel else {
            throw LocalTranscriptionError.unsupportedModel(model)
        }

        let runtime = await modelManager.runtimeStatus()
        guard runtime.isSupported else {
            throw LocalTranscriptionError.unsupportedHardware(runtime.message)
        }

        let installState = await modelManager.installState(for: model)
        await routeTracker?.record(
            LocalTranscriptionRouteResolution(
                configuredMode: options.localEngineMode ?? .whisperKit,
                resolvedBackend: .whisperKitSDK,
                selectedModel: model,
                serverConnectionMode: nil,
                lifecycleState: installState.lifecycleIdentifier,
                message: nil,
                usedLegacyFallback: false
            )
        )
        let modelDirectoryURL: URL
        switch installState {
        case .ready(let installedURL):
            modelDirectoryURL = installedURL
        case .downloaded:
            throw LocalTranscriptionError.whisperModelNeedsInstall(model)
        case .notDownloaded:
            throw LocalTranscriptionError.whisperModelNotInstalled(model)
        case .downloading:
            throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still downloading.")
        case .installing:
            throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still installing.")
        case .failed(let message):
            throw LocalTranscriptionError.whisperRuntimeUnavailable(message)
        }

        let config = WhisperKitConfig(
            model: model.whisperKitModelName,
            modelFolder: modelDirectoryURL.path,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        let decodeOptions = DecodingOptions(
            verbose: false,
            withoutTimestamps: false,
            wordTimestamps: true
        )

        do {
            let pipe = try await WhisperKit(config)
            let results = try await pipe.transcribe(audioPath: audioFileURL.path, decodeOptions: decodeOptions)
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

            guard !rawText.isEmpty else {
                throw LocalTranscriptionError.noTranscriptionResult
            }

            return Transcript(
                rawText: rawText,
                segments: segments,
                tokenLogprobs: nil,
                lowConfidenceSpans: [],
                modelID: model.rawValue,
                responseFormat: "text"
            )
        } catch {
            throw LocalTranscriptionError.whisperTranscriptionFailed(error.localizedDescription)
        }
    }
}

final class WhisperKitServerManager: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func status(
        connectionMode: WhisperKitServerConnectionMode,
        externalBaseURL: String?
    ) async -> WhisperKitServerStatus {
        switch connectionMode {
        case .managedHelper:
            do {
                _ = try runManagedHelper(arguments: ["health"])
                return WhisperKitServerStatus(isReachable: true, message: "Managed WhisperKit helper is available.", activeModel: nil)
            } catch {
                return WhisperKitServerStatus(isReachable: false, message: error.localizedDescription, activeModel: nil)
            }
        case .externalServer:
            guard let baseURL = normalizedBaseURL(from: externalBaseURL) else {
                return WhisperKitServerStatus(isReachable: false, message: "Set a WhisperKit server URL first.", activeModel: nil)
            }
            guard let url = URL(string: "\(baseURL)/health") else {
                return WhisperKitServerStatus(isReachable: false, message: "WhisperKit server URL is invalid.", activeModel: nil)
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    return WhisperKitServerStatus(isReachable: false, message: "WhisperKit server returned HTTP \(statusCode).", activeModel: nil)
                }
                return WhisperKitServerStatus(isReachable: true, message: "External WhisperKit server is reachable.", activeModel: nil)
            } catch {
                return WhisperKitServerStatus(isReachable: false, message: "Could not reach WhisperKit server: \(error.localizedDescription)", activeModel: nil)
            }
        }
    }

    func transcribe(
        audioFileURL: URL,
        model: LocalTranscriptionModel,
        connectionMode: WhisperKitServerConnectionMode,
        externalBaseURL: String?
    ) async throws -> Transcript {
        switch connectionMode {
        case .managedHelper:
            let response = try runManagedHelper(arguments: [
                "transcribe",
                "--audio-path", audioFileURL.path,
                "--model", model.whisperKitModelName ?? model.rawValue
            ])
            let payload = try JSONDecoder().decode(ManagedWhisperKitHelperResponse.self, from: response)
            guard payload.success else {
                throw LocalTranscriptionError.whisperTranscriptionFailed(payload.message ?? "Managed WhisperKit helper failed.")
            }
            return payload.transcript ?? Transcript.empty(modelID: model.rawValue, responseFormat: "text")
        case .externalServer:
            guard let baseURL = normalizedBaseURL(from: externalBaseURL) else {
                throw LocalTranscriptionError.whisperTranscriptionFailed("WhisperKit server URL is missing.")
            }
            guard let url = URL(string: "\(baseURL)/v1/audio/transcriptions") else {
                throw LocalTranscriptionError.whisperTranscriptionFailed("WhisperKit server URL is invalid.")
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = try multipartBody(audioFileURL: audioFileURL, modelName: model.whisperKitModelName ?? model.rawValue, boundary: boundary)

            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LocalTranscriptionError.whisperTranscriptionFailed("WhisperKit server returned HTTP \(statusCode). \(body)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw LocalTranscriptionError.noTranscriptionResult
                }
                return Transcript(
                    rawText: trimmed,
                    segments: [],
                    tokenLogprobs: nil,
                    lowConfidenceSpans: [],
                    modelID: model.rawValue,
                    responseFormat: "json"
                )
            }

            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                throw LocalTranscriptionError.noTranscriptionResult
            }
            return Transcript(
                rawText: text,
                segments: [],
                tokenLogprobs: nil,
                lowConfidenceSpans: [],
                modelID: model.rawValue,
                responseFormat: "text"
            )
        }
    }

    private func normalizedBaseURL(from input: String?) -> String? {
        guard let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private func runManagedHelper(arguments: [String]) throws -> Data {
        guard let executableURL = Bundle.main.executableURL else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Managed WhisperKit helper executable is unavailable.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--whisperkit-helper"] + arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdoutData = output.fileHandleForReading.readDataToEndOfFile()
        let stderrData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw LocalTranscriptionError.whisperTranscriptionFailed(
                stderrText.isEmpty ? "Managed WhisperKit helper failed to start." : stderrText
            )
        }

        return stdoutData
    }

    private func multipartBody(audioFileURL: URL, modelName: String, boundary: String) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        let audioData = try Data(contentsOf: audioFileURL)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("\(modelName)\(lineBreak)".data(using: .utf8)!)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(audioData)
        body.append(lineBreak.data(using: .utf8)!)
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        return body
    }
}

struct ManagedWhisperKitHelperResponse: Codable {
    let success: Bool
    let message: String?
    let transcript: Transcript?
}
