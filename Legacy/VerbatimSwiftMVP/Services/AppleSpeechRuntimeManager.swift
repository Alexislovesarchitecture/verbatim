@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

enum AppleSpeechAssetState: String, Codable, Sendable {
    case ready
    case installRequired = "install_required"
    case installing
    case unsupportedLocale = "unsupported_locale"
    case unavailable
    case failed
}

struct AppleSpeechRuntimeStatus: Equatable, Sendable {
    static let pendingCheckMessage = "Checking Apple Dictation readiness..."

    let lifecycleState: AppleSpeechAssetState
    let message: String
    let resolvedLocale: Locale?
    let installationProgress: Double?
    let canInstallAssets: Bool

    var isReady: Bool {
        lifecycleState == .ready
    }

    var isInstallingAssets: Bool {
        lifecycleState == .installing
    }

    var isPendingCheck: Bool {
        message == Self.pendingCheckMessage
    }

    var lifecycleIdentifier: String {
        lifecycleState.rawValue
    }

    static func ready(locale: Locale) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .ready,
            message: "Apple Dictation assets are installed for \(locale.identifier).",
            resolvedLocale: locale,
            installationProgress: nil,
            canInstallAssets: false
        )
    }

    static func installing(locale: Locale?, progress: Double?) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .installing,
            message: "Installing Apple Dictation assets" + Self.progressSuffix(progress),
            resolvedLocale: locale,
            installationProgress: progress,
            canInstallAssets: false
        )
    }

    static func installRequired(locale: Locale) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .installRequired,
            message: "Apple Dictation assets for \(locale.identifier) are available but not installed yet.",
            resolvedLocale: locale,
            installationProgress: nil,
            canInstallAssets: true
        )
    }

    static func unsupportedLocale(_ locale: Locale) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .unsupportedLocale,
            message: "Apple Dictation does not support the current locale (\(locale.identifier)).",
            resolvedLocale: nil,
            installationProgress: nil,
            canInstallAssets: false
        )
    }

    static func unavailable(message: String, locale: Locale?) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .unavailable,
            message: message,
            resolvedLocale: locale,
            installationProgress: nil,
            canInstallAssets: false
        )
    }

    static func failed(message: String, locale: Locale?, canInstallAssets: Bool) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .failed,
            message: message,
            resolvedLocale: locale,
            installationProgress: nil,
            canInstallAssets: canInstallAssets
        )
    }

    static func pendingCheck(locale: Locale) -> AppleSpeechRuntimeStatus {
        AppleSpeechRuntimeStatus(
            lifecycleState: .failed,
            message: pendingCheckMessage,
            resolvedLocale: locale,
            installationProgress: nil,
            canInstallAssets: false
        )
    }

    private static func progressSuffix(_ progress: Double?) -> String {
        guard let progress else { return "…" }
        return String(format: " (%d%%)…", Int((progress * 100).rounded()))
    }
}

struct AppleSpeechRecognitionSnapshot: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let start: TimeInterval?
        let end: TimeInterval?
        let text: String
    }

    let text: String
    let segments: [Segment]
}

enum AppleSpeechRuntimeError: LocalizedError {
    case unsupportedLocale(String)
    case assetsNotInstalled(String)
    case assetsInstalling(String)
    case installationFailed(String)
    case runtimeUnavailable(String)
    case analyzerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let message),
                .assetsNotInstalled(let message),
                .assetsInstalling(let message),
                .installationFailed(let message),
                .runtimeUnavailable(let message),
                .analyzerFailed(let message):
            return message
        }
    }
}

protocol AppleSpeechRuntimeManaging: Sendable {
    func status(for preferredLocale: Locale) async -> AppleSpeechRuntimeStatus
    func installAssets(
        for preferredLocale: Locale,
        progress: (@Sendable (Double?) async -> Void)?
    ) async throws -> AppleSpeechRuntimeStatus
    func transcribe(audioFileURL: URL, preferredLocale: Locale) async throws -> AppleSpeechRecognitionSnapshot
}

protocol AppleSpeechPermissionProviding: Sendable {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus
    func requestMicrophoneAccess() async -> Bool
    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
}

struct LiveAppleSpeechPermissionProvider: AppleSpeechPermissionProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

actor AppleSpeechRuntimeManager: AppleSpeechRuntimeManaging {
    private enum ResolvedLocaleStatus {
        case success(Locale)
        case failure(AppleSpeechRuntimeStatus)
    }

    private struct InstallationState: Sendable {
        var isInstalling = false
        var progress: Double?
        var lastFailureMessage: String?
    }

    private let fileManager: FileManager
    private var installationState = InstallationState()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func status(for preferredLocale: Locale) async -> AppleSpeechRuntimeStatus {
        let localeStatus = await resolvedLocaleStatus(for: preferredLocale)
        switch localeStatus {
        case .failure(let status):
            return status
        case .success(let locale):
            if installationState.isInstalling {
                return .installing(locale: locale, progress: installationState.progress)
            }

            let module = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
            let assetStatus = await AssetInventory.status(forModules: [module])

            switch assetStatus {
            case .installed:
                installationState.lastFailureMessage = nil
                return .ready(locale: locale)
            case .downloading:
                return .installing(locale: locale, progress: installationState.progress)
            case .supported:
                if let failureMessage = installationState.lastFailureMessage {
                    return .failed(message: failureMessage, locale: locale, canInstallAssets: true)
                }
                return .installRequired(locale: locale)
            case .unsupported:
                if let failureMessage = installationState.lastFailureMessage {
                    return .failed(message: failureMessage, locale: locale, canInstallAssets: false)
                }
                return .unavailable(
                    message: "Apple Dictation assets are unavailable for \(locale.identifier).",
                    locale: locale
                )
            @unknown default:
                return .unavailable(
                    message: "Apple Dictation returned an unknown asset state.",
                    locale: locale
                )
            }
        }
    }

    func installAssets(
        for preferredLocale: Locale,
        progress: (@Sendable (Double?) async -> Void)? = nil
    ) async throws -> AppleSpeechRuntimeStatus {
        let localeStatus = await resolvedLocaleStatus(for: preferredLocale)
        let locale: Locale
        switch localeStatus {
        case .failure(let status):
            throw AppleSpeechRuntimeError.unsupportedLocale(status.message)
        case .success(let resolvedLocale):
            locale = resolvedLocale
        }

        let module = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let assetStatus = await AssetInventory.status(forModules: [module])
        switch assetStatus {
        case .installed:
            installationState.lastFailureMessage = nil
            return .ready(locale: locale)
        case .unsupported:
            throw AppleSpeechRuntimeError.runtimeUnavailable("Apple Dictation assets are unavailable for \(locale.identifier).")
        case .supported, .downloading:
            break
        @unknown default:
            throw AppleSpeechRuntimeError.runtimeUnavailable("Apple Dictation returned an unknown asset state.")
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            return await status(for: preferredLocale)
        }

        installationState.isInstalling = true
        installationState.progress = 0
        installationState.lastFailureMessage = nil
        await progress?(0)

        let progressTask = Task { [weak request] in
            while !Task.isCancelled {
                let fractionCompleted = request?.progress.isIndeterminate == true
                    ? nil
                    : request?.progress.fractionCompleted
                self.updateInstallationProgress(fractionCompleted)
                await progress?(fractionCompleted)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        do {
            try await request.downloadAndInstall()
            progressTask.cancel()
            updateInstallationProgress(1)
            await progress?(1)
            installationState.isInstalling = false
            installationState.lastFailureMessage = nil
            return await status(for: preferredLocale)
        } catch {
            progressTask.cancel()
            installationState.isInstalling = false
            installationState.progress = nil
            installationState.lastFailureMessage = "Apple Dictation asset installation failed: \(error.localizedDescription)"
            throw AppleSpeechRuntimeError.installationFailed(
                installationState.lastFailureMessage ?? "Apple Dictation asset installation failed."
            )
        }
    }

    func transcribe(audioFileURL: URL, preferredLocale: Locale) async throws -> AppleSpeechRecognitionSnapshot {
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }

        let runtimeStatus = await status(for: preferredLocale)
        switch runtimeStatus.lifecycleState {
        case .ready:
            break
        case .installRequired:
            throw AppleSpeechRuntimeError.assetsNotInstalled(runtimeStatus.message)
        case .installing:
            throw AppleSpeechRuntimeError.assetsInstalling(runtimeStatus.message)
        case .unsupportedLocale:
            throw AppleSpeechRuntimeError.unsupportedLocale(runtimeStatus.message)
        case .unavailable:
            throw AppleSpeechRuntimeError.runtimeUnavailable(runtimeStatus.message)
        case .failed:
            throw AppleSpeechRuntimeError.installationFailed(runtimeStatus.message)
        }

        guard let locale = runtimeStatus.resolvedLocale else {
            throw AppleSpeechRuntimeError.unsupportedLocale("Apple Dictation could not resolve a supported locale.")
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioFileURL)
            let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
            let analyzer = try await SpeechAnalyzer(
                inputAudioFile: audioFile,
                modules: [transcriber],
                finishAfterFile: true
            )

            let resultsTask = Task { () throws -> [DictationTranscriber.Result] in
                var finalResultsByRange: [String: DictationTranscriber.Result] = [:]
                var resultOrder: [String] = []
                for try await result in transcriber.results {
                    guard result.isFinal else { continue }
                    let key = Self.rangeKey(for: result.range)
                    if finalResultsByRange[key] == nil {
                        resultOrder.append(key)
                    }
                    finalResultsByRange[key] = result
                }

                return resultOrder.compactMap { finalResultsByRange[$0] }
            }

            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let finalResults = try await resultsTask.value
            let snapshot = Self.makeSnapshot(from: finalResults)
            guard snapshot.text.isEmpty == false else {
                throw LocalTranscriptionError.noTranscriptionResult
            }
            return snapshot
        } catch let error as LocalTranscriptionError {
            throw error
        } catch let error as AppleSpeechRuntimeError {
            throw error
        } catch {
            throw AppleSpeechRuntimeError.analyzerFailed("Apple Dictation failed: \(error.localizedDescription)")
        }
    }

    private func resolvedLocaleStatus(for preferredLocale: Locale) async -> ResolvedLocaleStatus {
        guard SpeechTranscriber.isAvailable else {
            return .failure(
                .unavailable(
                    message: "Apple Dictation is unavailable on this Mac.",
                    locale: preferredLocale
                )
            )
        }

        if let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: preferredLocale) {
            return .success(resolvedLocale)
        }

        return .failure(.unsupportedLocale(preferredLocale))
    }

    private func updateInstallationProgress(_ progress: Double?) {
        installationState.progress = progress
    }

    private static func makeSnapshot(from results: [DictationTranscriber.Result]) -> AppleSpeechRecognitionSnapshot {
        let orderedResults = results.sorted {
            let lhs = Self.seconds(from: $0.range.start) ?? -.greatestFiniteMagnitude
            let rhs = Self.seconds(from: $1.range.start) ?? -.greatestFiniteMagnitude
            return lhs < rhs
        }

        let text = collapseWhitespace(
            orderedResults
                .map { String($0.text.characters) }
                .joined(separator: " ")
        )

        var segments: [AppleSpeechRecognitionSnapshot.Segment] = []
        for result in orderedResults {
            let extractedSegments = extractSegments(from: result)
            if extractedSegments.isEmpty {
                let fallbackText = collapseWhitespace(String(result.text.characters))
                if fallbackText.isEmpty == false {
                    segments.append(
                        AppleSpeechRecognitionSnapshot.Segment(
                            start: seconds(from: result.range.start),
                            end: seconds(from: CMTimeRangeGetEnd(result.range)),
                            text: fallbackText
                        )
                    )
                }
            } else {
                segments.append(contentsOf: extractedSegments)
            }
        }

        return AppleSpeechRecognitionSnapshot(text: text, segments: segments)
    }

    private static func extractSegments(from result: DictationTranscriber.Result) -> [AppleSpeechRecognitionSnapshot.Segment] {
        var segments: [AppleSpeechRecognitionSnapshot.Segment] = []
        for run in result.text.runs {
            let runText = collapseWhitespace(String(result.text[run.range].characters))
            guard runText.isEmpty == false else { continue }
            let timeRange = run.attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
            segments.append(
                AppleSpeechRecognitionSnapshot.Segment(
                    start: timeRange.flatMap { seconds(from: $0.start) },
                    end: timeRange.flatMap { seconds(from: CMTimeRangeGetEnd($0)) },
                    text: runText
                )
            )
        }
        return segments
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func seconds(from time: CMTime) -> TimeInterval? {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return nil }
        return seconds
    }

    private static func rangeKey(for range: CMTimeRange) -> String {
        let start = seconds(from: range.start) ?? -1
        let end = seconds(from: CMTimeRangeGetEnd(range)) ?? -1
        return "\(start)-\(end)"
    }
}
