import Foundation

enum RecordingTriggerSource: String, Codable, Sendable {
    case manual
    case hotkey
}

enum RecordingInsertionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case autoPasteWhenPossible = "auto_paste_when_possible"
    case copyOnly = "copy_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoPasteWhenPossible:
            return "Auto-paste when possible"
        case .copyOnly:
            return "Copy only"
        }
    }
}

enum ClipboardRestoreMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualOnly = "manual_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualOnly:
            return "Manual only"
        }
    }
}

enum SilenceSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }
}

struct AudioActivitySummary: Equatable, Sendable {
    let averagePower: Double
    let peakLevel: Double
    let voicedDuration: TimeInterval
    let totalDuration: TimeInterval
    let speechDetected: Bool

    var hasUsableSpeech: Bool {
        speechDetected && voicedDuration > 0
    }

    var voicedRatio: Double {
        guard totalDuration > 0 else { return 0 }
        return voicedDuration / totalDuration
    }
}

struct RecordingSessionContext: Sendable {
    let sessionID: UUID
    let targetBundleID: String?
    let targetAppName: String?
    let targetPID: pid_t?
    let targetWindowTitle: String?
    let targetElementRole: String?
    let appStyleCategory: StyleCategory
    let activeAppContext: ActiveAppContext
    let insertionTarget: InsertionTarget?
    let stylePreset: StylePreset?
    let startedAt: Date
    let triggerSource: RecordingTriggerSource
    let triggerMode: HotkeyTriggerMode?
    let lockTargetAtStart: Bool
    let audioActivitySummary: AudioActivitySummary?

    init(
        sessionID: UUID = UUID(),
        activeAppContext: ActiveAppContext,
        insertionTarget: InsertionTarget?,
        stylePreset: StylePreset? = nil,
        startedAt: Date = Date(),
        triggerSource: RecordingTriggerSource,
        triggerMode: HotkeyTriggerMode? = nil,
        lockTargetAtStart: Bool? = nil,
        audioActivitySummary: AudioActivitySummary? = nil
    ) {
        self.sessionID = sessionID
        self.targetBundleID = activeAppContext.bundleID
        self.targetAppName = activeAppContext.appName
        self.targetPID = activeAppContext.processIdentifier
        self.targetWindowTitle = activeAppContext.windowTitle
        self.targetElementRole = activeAppContext.focusedElementRole
        self.appStyleCategory = activeAppContext.styleCategory
        self.activeAppContext = activeAppContext
        self.insertionTarget = insertionTarget
        self.stylePreset = stylePreset
        self.startedAt = startedAt
        self.triggerSource = triggerSource
        self.triggerMode = triggerMode
        self.lockTargetAtStart = lockTargetAtStart ?? (triggerSource == .hotkey)
        self.audioActivitySummary = audioActivitySummary
    }

    var requiresFrozenInsertionTarget: Bool {
        lockTargetAtStart
    }

    var shouldGateSilenceBeforeTranscription: Bool {
        triggerSource == .hotkey
    }

    func withAudioActivitySummary(_ summary: AudioActivitySummary) -> RecordingSessionContext {
        RecordingSessionContext(
            sessionID: sessionID,
            activeAppContext: activeAppContext,
            insertionTarget: insertionTarget,
            stylePreset: stylePreset,
            startedAt: startedAt,
            triggerSource: triggerSource,
            triggerMode: triggerMode,
            lockTargetAtStart: lockTargetAtStart,
            audioActivitySummary: summary
        )
    }
}

struct RecordingSession: Sendable {
    let context: RecordingSessionContext
    var silenceAnalysis: AudioActivitySummary?
    var audioFileURL: URL?
    let startedAt: Date

    init(
        context: RecordingSessionContext,
        silenceAnalysis: AudioActivitySummary? = nil,
        audioFileURL: URL? = nil,
        startedAt: Date? = nil
    ) {
        self.context = context
        self.silenceAnalysis = silenceAnalysis
        self.audioFileURL = audioFileURL
        self.startedAt = startedAt ?? context.startedAt
    }
}

enum RecordingCompletionResult: Sendable {
    case transcribed(RecordingSessionContext?)
    case skippedSilence(RecordingSessionContext)
    case failed(message: String, context: RecordingSessionContext?)
}

enum ClipboardFallbackReason: Equatable, Sendable {
    case autoPasteDisabled
    case accessibilityPermissionRequired
    case missingInsertionTarget
    case invalidTargetApplication
    case targetRestoreFailed
    case pasteFailed

    var userMessage: String {
        switch self {
        case .autoPasteDisabled:
            return "Copied to clipboard. Paste manually."
        case .accessibilityPermissionRequired:
            return "Copied to clipboard. Paste manually or enable Accessibility."
        case .missingInsertionTarget:
            return "Copied to clipboard. Original text field was unavailable."
        case .invalidTargetApplication:
            return "Original target unavailable. Copied to clipboard."
        case .targetRestoreFailed, .pasteFailed:
            return "Copied to clipboard. Paste manually in the target app."
        }
    }
}

enum InsertionFailureReason: Equatable, Sendable {
    case emptyText
    case clipboardWriteFailed
}

enum InsertionResult: Equatable, Sendable {
    case pasted
    case copiedOnly(reason: ClipboardFallbackReason)
    case copiedOnlyNeedsPermission
    case failed(reason: InsertionFailureReason)

    var userMessage: String {
        switch self {
        case .pasted:
            return "Inserted."
        case .copiedOnly(let reason):
            return reason.userMessage
        case .copiedOnlyNeedsPermission:
            return ClipboardFallbackReason.accessibilityPermissionRequired.userMessage
        case .failed(let reason):
            switch reason {
            case .emptyText:
                return "Nothing to insert."
            case .clipboardWriteFailed:
                return "Could not copy text to the clipboard."
            }
        }
    }

    var persistedOutcome: InsertionOutcome {
        switch self {
        case .pasted:
            return .inserted
        case .copiedOnly:
            return .copiedOnly
        case .copiedOnlyNeedsPermission:
            return .copiedOnlyNeedsPermission
        case .failed:
            return .failed
        }
    }

    var fallbackReason: ClipboardFallbackReason? {
        switch self {
        case .copiedOnly(let reason):
            return reason
        case .copiedOnlyNeedsPermission:
            return .accessibilityPermissionRequired
        case .pasted, .failed:
            return nil
        }
    }
}

struct DiagnosticSessionRecord: Identifiable, Equatable, Sendable {
    let sessionID: UUID
    let startedAt: Date
    let durationMs: Int
    let triggerSource: RecordingTriggerSource
    let triggerMode: HotkeyTriggerMode?
    let transcriptionEngine: String?
    let localEngineMode: String?
    let resolvedBackend: String?
    let serverConnectionMode: String?
    let modelID: String?
    let localModelLifecycleState: String?
    let logicModelID: String?
    let reasoningEffort: String?
    let formattingProfile: String?
    let transcriptionLatencyMs: Int?
    let llmLatencyMs: Int?
    let totalLatencyMs: Int?
    let tokensIn: Int?
    let cachedTokens: Int?
    let insertionOutcome: InsertionOutcome?
    let fallbackReason: ClipboardFallbackReason?
    let targetApp: String?
    let targetBundleID: String?
    let silencePeak: Double?
    let silenceAverageRMS: Double?
    let silenceVoicedRatio: Double?
    let skippedForSilence: Bool
    let failureMessage: String?

    init(
        sessionID: UUID,
        startedAt: Date,
        durationMs: Int,
        triggerSource: RecordingTriggerSource,
        triggerMode: HotkeyTriggerMode?,
        transcriptionEngine: String?,
        localEngineMode: String? = nil,
        resolvedBackend: String? = nil,
        serverConnectionMode: String? = nil,
        modelID: String?,
        localModelLifecycleState: String? = nil,
        logicModelID: String?,
        reasoningEffort: String?,
        formattingProfile: String?,
        transcriptionLatencyMs: Int?,
        llmLatencyMs: Int?,
        totalLatencyMs: Int?,
        tokensIn: Int?,
        cachedTokens: Int?,
        insertionOutcome: InsertionOutcome?,
        fallbackReason: ClipboardFallbackReason?,
        targetApp: String?,
        targetBundleID: String?,
        silencePeak: Double?,
        silenceAverageRMS: Double?,
        silenceVoicedRatio: Double?,
        skippedForSilence: Bool,
        failureMessage: String? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.triggerSource = triggerSource
        self.triggerMode = triggerMode
        self.transcriptionEngine = transcriptionEngine
        self.localEngineMode = localEngineMode
        self.resolvedBackend = resolvedBackend
        self.serverConnectionMode = serverConnectionMode
        self.modelID = modelID
        self.localModelLifecycleState = localModelLifecycleState
        self.logicModelID = logicModelID
        self.reasoningEffort = reasoningEffort
        self.formattingProfile = formattingProfile
        self.transcriptionLatencyMs = transcriptionLatencyMs
        self.llmLatencyMs = llmLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.tokensIn = tokensIn
        self.cachedTokens = cachedTokens
        self.insertionOutcome = insertionOutcome
        self.fallbackReason = fallbackReason
        self.targetApp = targetApp
        self.targetBundleID = targetBundleID
        self.silencePeak = silencePeak
        self.silenceAverageRMS = silenceAverageRMS
        self.silenceVoicedRatio = silenceVoicedRatio
        self.skippedForSilence = skippedForSilence
        self.failureMessage = failureMessage
    }

    var id: UUID { sessionID }
}

struct DiagnosticSessionSummary: Equatable, Sendable {
    let averageTotalLatencyMs: Int?
    let cacheHitRate: Double
    let silenceSkipRate: Double
    let pasteFailureRate: Double
    let permissionFallbackCount: Int

    static let empty = DiagnosticSessionSummary(
        averageTotalLatencyMs: nil,
        cacheHitRate: 0,
        silenceSkipRate: 0,
        pasteFailureRate: 0,
        permissionFallbackCount: 0
    )
}

enum DiagnosticsSessionLimit: Int, CaseIterable, Identifiable, Sendable {
    case last20 = 20
    case last100 = 100

    var id: Int { rawValue }

    var title: String {
        "Last \(rawValue)"
    }
}
