import Foundation
import WhisperKit

struct LocalTranscriptionRouteResolution: Equatable, Sendable {
    let configuredMode: LocalTranscriptionEngineMode
    let resolvedBackend: LocalTranscriptionBackend
    let selectedModel: LocalTranscriptionModel
    let transport: LocalTranscriptionTransport?
    let serverConnectionMode: WhisperKitServerConnectionMode?
    let lifecycleState: String?
    let helperState: ManagedWhisperKitHelperState?
    let prewarmState: ManagedWhisperKitPrewarmState?
    let failureStage: LocalTranscriptionFailureStage?
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
        LocalRuntimePaths(fileManager: fileManager, baseDirectoryURL: baseDirectoryURL).whisperKitRoot
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
    private let serverManager: WhisperKitServerManager

    init(
        modelManager: WhisperKitModelManager,
        routeTracker: LocalTranscriptionRouteTracker? = nil,
        serverManager: WhisperKitServerManager = WhisperKitServerManager()
    ) {
        self.modelManager = modelManager
        self.routeTracker = routeTracker
        self.serverManager = serverManager
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let selectedModel = LocalTranscriptionModel(rawValue: options.modelID) ?? .whisperBase
        return try await transcribe(audioFileURL: audioURL, model: selectedModel, options: options)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        try await transcribe(
            audioFileURL: audioFileURL,
            model: model,
            options: TranscriptionOptions(
                modelID: model.rawValue,
                responseFormat: "text",
                whisperKitServerConnectionMode: .managedHelper
            )
        )
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

        let connectionMode = options.whisperKitServerConnectionMode ?? .managedHelper
        if connectionMode == .externalServer {
            do {
                let transcript = try await serverManager.transcribeExternal(
                    audioFileURL: audioFileURL,
                    model: model,
                    externalBaseURL: options.whisperKitServerBaseURL
                )
                await recordRoute(
                    model: model,
                    options: options,
                    installState: "external_server",
                    transport: .externalServer,
                    serverConnectionMode: connectionMode,
                    helperMetadata: nil,
                    failureStage: nil,
                    message: nil
                )
                return transcript
            } catch {
                await recordRoute(
                    model: model,
                    options: options,
                    installState: "external_server",
                    transport: .externalServer,
                    serverConnectionMode: connectionMode,
                    helperMetadata: nil,
                    failureStage: .inference,
                    message: error.localizedDescription
                )
                throw LocalTranscriptionError.whisperTranscriptionFailed(error.localizedDescription)
            }
        }

        let runtime = await modelManager.runtimeStatus()
        guard runtime.isSupported else {
            throw LocalTranscriptionError.unsupportedHardware(runtime.message)
        }

        let installState = await modelManager.installState(for: model)
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

        switch connectionMode {
        case .managedHelper:
            do {
                let runtimeMetadata = try await serverManager.ensureManagedRuntimeRunning()
                await recordRoute(
                    model: model,
                    options: options,
                    installState: installState.lifecycleIdentifier,
                    transport: .managedHelper,
                    serverConnectionMode: connectionMode,
                    helperMetadata: runtimeMetadata,
                    failureStage: nil,
                    message: nil
                )
                let transcript = try await serverManager.transcribeManagedRuntime(
                    audioFileURL: audioFileURL,
                    model: model,
                    modelDirectoryURL: modelDirectoryURL
                )
                let latestMetadata = await serverManager.managedRuntimeMetadata()
                await recordRoute(
                    model: model,
                    options: options,
                    installState: installState.lifecycleIdentifier,
                    transport: .managedHelper,
                    serverConnectionMode: connectionMode,
                    helperMetadata: latestMetadata,
                    failureStage: nil,
                    message: nil
                )
                return transcript
            } catch {
                let latestMetadata = await serverManager.managedRuntimeMetadata()
                await recordRoute(
                    model: model,
                    options: options,
                    installState: installState.lifecycleIdentifier,
                    transport: .managedHelper,
                    serverConnectionMode: connectionMode,
                    helperMetadata: latestMetadata,
                    failureStage: failureStage(for: error),
                    message: error.localizedDescription
                )
                throw mapManagedRuntimeError(error)
            }
        case .externalServer:
            fatalError("External server path should return before local WhisperKit install checks.")
        }
    }

    private func recordRoute(
        model: LocalTranscriptionModel,
        options: TranscriptionOptions,
        installState: String?,
        transport: LocalTranscriptionTransport,
        serverConnectionMode: WhisperKitServerConnectionMode?,
        helperMetadata: ManagedWhisperKitRuntimeMetadata?,
        failureStage: LocalTranscriptionFailureStage?,
        message: String?
    ) async {
        await routeTracker?.record(
            LocalTranscriptionRouteResolution(
                configuredMode: options.localEngineMode ?? .whisperKit,
                resolvedBackend: .whisperKitSDK,
                selectedModel: model,
                transport: transport,
                serverConnectionMode: serverConnectionMode,
                lifecycleState: installState,
                helperState: helperMetadata?.helperState,
                prewarmState: helperMetadata?.prewarmState,
                failureStage: failureStage,
                message: message ?? helperMetadata?.lastFailureMessage,
                usedLegacyFallback: false
            )
        )
    }

    private func failureStage(for error: Error) -> LocalTranscriptionFailureStage? {
        if error is LocalTranscriptionError {
            return .convert
        }
        guard let runtimeError = error as? ManagedWhisperKitRuntimeError else {
            return nil
        }
        switch runtimeError {
        case .executableUnavailable, .launchFailed:
            return .launch
        case .healthCheckFailed:
            return .health
        case .inferenceFailed:
            return .inference
        case .invalidResponse:
            return .responseParse
        }
    }

    private func mapManagedRuntimeError(_ error: Error) -> Error {
        if let localError = error as? LocalTranscriptionError {
            return localError
        }

        guard let runtimeError = error as? ManagedWhisperKitRuntimeError else {
            return LocalTranscriptionError.whisperTranscriptionFailed(error.localizedDescription)
        }

        switch runtimeError {
        case .executableUnavailable, .launchFailed, .healthCheckFailed:
            return LocalTranscriptionError.whisperRuntimeUnavailable(runtimeError.localizedDescription)
        case .inferenceFailed, .invalidResponse:
            return LocalTranscriptionError.whisperTranscriptionFailed(runtimeError.localizedDescription)
        }
    }
}

final class WhisperKitServerManager: @unchecked Sendable {
    private enum ExternalWhisperRequestError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    private let session: URLSession
    private let managedRuntime: ManagedWhisperKitRuntimeProtocol

    init(
        session: URLSession = .shared,
        managedRuntime: ManagedWhisperKitRuntimeProtocol = ManagedWhisperKitRuntime()
    ) {
        self.session = session
        self.managedRuntime = managedRuntime
    }

    func status(
        connectionMode: WhisperKitServerConnectionMode,
        externalBaseURL: String?
    ) async -> WhisperKitServerStatus {
        switch connectionMode {
        case .managedHelper:
            do {
                let metadata = try await managedRuntime.ensureRunning()
                return WhisperKitServerStatus(
                    isReachable: metadata.helperState == .running,
                    message: metadata.lastFailureMessage ?? "Managed WhisperKit helper is available.",
                    activeModel: metadata.activeModel
                )
            } catch {
                return WhisperKitServerStatus(isReachable: false, message: error.localizedDescription, activeModel: nil)
            }
        case .externalServer:
            guard let baseURL = normalizedBaseURL(from: externalBaseURL) else {
                return WhisperKitServerStatus(isReachable: false, message: "Set a WhisperKit server URL first.", activeModel: nil)
            }
            let healthPaths = ["/health", "/"]
            for path in healthPaths {
                guard let url = URL(string: "\(baseURL)\(path)") else {
                    continue
                }
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (data, response) = try await session.data(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(statusCode) else {
                        continue
                    }
                    let activeModel = parseActiveModel(from: data)
                    return WhisperKitServerStatus(
                        isReachable: true,
                        message: path == "/" ? "OpenWhispr-style Whisper server is reachable." : "External Whisper server is reachable.",
                        activeModel: activeModel
                    )
                } catch {
                    continue
                }
            }
            return WhisperKitServerStatus(isReachable: false, message: "Could not reach external Whisper server at \(baseURL).", activeModel: nil)
        }
    }

    func ensureManagedRuntimeRunning() async throws -> ManagedWhisperKitRuntimeMetadata {
        try await managedRuntime.ensureRunning()
    }

    func managedRuntimeMetadata() async -> ManagedWhisperKitRuntimeMetadata {
        await managedRuntime.latestMetadata()
    }

    func prewarmManagedRuntime(
        model: LocalTranscriptionModel,
        modelDirectoryURL: URL
    ) async throws -> ManagedWhisperKitRuntimeMetadata {
        try await managedRuntime.prewarm(model: model, modelDirectoryURL: modelDirectoryURL)
    }

    func transcribeManagedRuntime(
        audioFileURL: URL,
        model: LocalTranscriptionModel,
        modelDirectoryURL: URL
    ) async throws -> Transcript {
        try await managedRuntime.transcribe(
            audioFileURL: audioFileURL,
            model: model,
            modelDirectoryURL: modelDirectoryURL
        )
    }

    func shutdownManagedRuntime() async {
        await managedRuntime.shutdown()
    }

    func transcribeExternal(
        audioFileURL: URL,
        model: LocalTranscriptionModel,
        externalBaseURL: String?
    ) async throws -> Transcript {
        guard let baseURL = normalizedBaseURL(from: externalBaseURL) else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("WhisperKit server URL is missing.")
        }
        let openAICompatibleAttempt = await sendExternalRequest(
            urlString: "\(baseURL)/v1/audio/transcriptions",
            model: model,
            body: try multipartBody(
                audioFileURL: audioFileURL,
                fields: [("model", model.whisperKitModelName ?? model.rawValue)]
            )
        )

        switch openAICompatibleAttempt {
        case .success(let transcript):
            return transcript
        case .failure(let firstFailure):
            let openWhisprAttempt = await sendExternalRequest(
                urlString: "\(baseURL)/inference",
                model: model,
                body: try multipartBody(
                    audioFileURL: audioFileURL,
                    fields: [("response_format", "json")]
                )
            )
            switch openWhisprAttempt {
            case .success(let transcript):
                return transcript
            case .failure(let secondFailure):
                throw LocalTranscriptionError.whisperTranscriptionFailed(
                    "External Whisper server failed. OpenAI-compatible attempt: \(firstFailure.localizedDescription) OpenWhispr-style attempt: \(secondFailure.localizedDescription)"
                )
            }
        }
    }

    private func normalizedBaseURL(from input: String?) -> String? {
        guard let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private func sendExternalRequest(
        urlString: String,
        model: LocalTranscriptionModel,
        body: MultipartRequestBody
    ) async -> Result<Transcript, ExternalWhisperRequestError> {
        guard let url = URL(string: urlString) else {
            return .failure(.message("Whisper server URL is invalid."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                return .failure(.message("HTTP \(statusCode). \(responseBody)"))
            }
            return .success(try parseTranscript(from: data, model: model))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    private func parseTranscript(from data: Data, model: LocalTranscriptionModel) throws -> Transcript {
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

    private func parseActiveModel(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let activeModel = json["activeModel"] as? String {
            return activeModel
        }
        if let model = json["model"] as? String {
            return model
        }
        return nil
    }

    private struct MultipartRequestBody {
        let boundary: String
        let data: Data
    }

    private func multipartBody(audioFileURL: URL, fields: [(String, String)]) throws -> MultipartRequestBody {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let lineBreak = "\r\n"
        let audioData = try Data(contentsOf: audioFileURL)

        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(audioData)
        body.append(lineBreak.data(using: .utf8)!)
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        return MultipartRequestBody(boundary: boundary, data: body)
    }
}

struct ManagedWhisperKitHelperResponse: Codable {
    let success: Bool
    let message: String?
    let transcript: Transcript?
}
