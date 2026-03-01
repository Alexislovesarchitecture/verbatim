import Foundation
import SwiftData

@Model
final class CaptureRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var sourceAppName: String
    var sourceBundleId: String?
    var durationMs: Int
    var wordCount: Int
    var wpm: Double
    var rawText: String
    var formattedText: String
    var resultStatus: CaptureStatus
    var errorMessage: String?
    var audioWasSilent: Bool
    var engineUsed: EngineUsed
    var wasLockedMode: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourceAppName: String = "Unknown",
        sourceBundleId: String? = nil,
        durationMs: Int,
        wordCount: Int,
        wpm: Double,
        rawText: String,
        formattedText: String,
        resultStatus: CaptureStatus,
        errorMessage: String? = nil,
        audioWasSilent: Bool = false,
        engineUsed: EngineUsed,
        wasLockedMode: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleId = sourceBundleId
        self.durationMs = durationMs
        self.wordCount = wordCount
        self.wpm = wpm
        self.rawText = rawText
        self.formattedText = formattedText
        self.resultStatus = resultStatus
        self.errorMessage = errorMessage
        self.audioWasSilent = audioWasSilent
        self.engineUsed = engineUsed
        self.wasLockedMode = wasLockedMode
    }
}

@Model
final class DictionaryEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var scope: DictionaryScope
    var kind: DictionaryKind
    var input: String
    var output: String?
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scope: DictionaryScope = .personal,
        kind: DictionaryKind = .term,
        input: String,
        output: String? = nil,
        enabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.scope = scope
        self.kind = kind
        self.input = input
        self.output = output
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SnippetEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var scope: SnippetScope
    var trigger: String
    var content: String
    var requireExactMatch: Bool
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scope: SnippetScope = .personal,
        trigger: String,
        content: String,
        requireExactMatch: Bool = false,
        enabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.scope = scope
        self.trigger = trigger
        self.content = content
        self.requireExactMatch = requireExactMatch
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class StyleProfile: Identifiable {
    @Attribute(.unique) var id: UUID
    var category: StyleCategory
    var tone: StyleTone
    var capsMode: CapsMode
    var punctuationMode: PunctuationMode
    var exclamationMode: ExclamationMode
    var removeFillers: Bool
    var interpretVoiceCommands: Bool
    var enabled: Bool

    init(
        id: UUID = UUID(),
        category: StyleCategory,
        tone: StyleTone = .casual,
        capsMode: CapsMode = .sentenceCase,
        punctuationMode: PunctuationMode = .normal,
        exclamationMode: ExclamationMode = .normal,
        removeFillers: Bool = true,
        interpretVoiceCommands: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.category = category
        self.tone = tone
        self.capsMode = capsMode
        self.punctuationMode = punctuationMode
        self.exclamationMode = exclamationMode
        self.removeFillers = removeFillers
        self.interpretVoiceCommands = interpretVoiceCommands
        self.enabled = enabled
    }
}

@Model
final class NoteEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var body: String
    var sourceCaptureId: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        body: String,
        sourceCaptureId: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.body = body
        self.sourceCaptureId = sourceCaptureId
    }
}

@Model
final class LocalBehaviorSettings {
    @Attribute(.unique) var id: UUID
    var biasTranscriptionWithDictionary: Bool
    var applyReplacementsAfterTranscription: Bool
    var enableSnippetExpansion: Bool
    var globalRequireExactMatch: Bool

    init(
        id: UUID = UUID(),
        biasTranscriptionWithDictionary: Bool = true,
        applyReplacementsAfterTranscription: Bool = true,
        enableSnippetExpansion: Bool = true,
        globalRequireExactMatch: Bool = false
    ) {
        self.id = id
        self.biasTranscriptionWithDictionary = biasTranscriptionWithDictionary
        self.applyReplacementsAfterTranscription = applyReplacementsAfterTranscription
        self.enableSnippetExpansion = enableSnippetExpansion
        self.globalRequireExactMatch = globalRequireExactMatch
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID

    var startSoundEnabled: Bool
    var stopSoundEnabled: Bool
    var doubleTapFnLockEnabled: Bool
    var overlayMeterEnabled: Bool
    var silenceThreshold: Float

    var provider: TranscriptionProvider
    var openAIModel: OpenAITranscriptionModel
    var openAIKeyRef: String
    var whisperCppPath: String
    var whisperModelPath: String
    var language: String

    var autoInsertEnabled: Bool
    var clipboardFallbackEnabled: Bool
    var showCapturedToastEnabled: Bool
    var insertionModePreferred: InsertionModePreferred

    var historyRetentionDays: Int
    var autoSaveLongCapturesToNotes: Bool
    var longCaptureThresholdWords: Int

    init(
        id: UUID = UUID(),
        startSoundEnabled: Bool = true,
        stopSoundEnabled: Bool = true,
        doubleTapFnLockEnabled: Bool = true,
        overlayMeterEnabled: Bool = true,
        silenceThreshold: Float = 0.06,
        provider: TranscriptionProvider = .openai,
        openAIModel: OpenAITranscriptionModel = .gpt4oMiniTranscribe,
        openAIKeyRef: String = "",
        whisperCppPath: String = "/opt/homebrew/bin/whisper-cli",
        whisperModelPath: String = "",
        language: String = "en",
        autoInsertEnabled: Bool = true,
        clipboardFallbackEnabled: Bool = true,
        showCapturedToastEnabled: Bool = true,
        insertionModePreferred: InsertionModePreferred = .accessibilityFirst,
        historyRetentionDays: Int = 30,
        autoSaveLongCapturesToNotes: Bool = false,
        longCaptureThresholdWords: Int = 120
    ) {
        self.id = id
        self.startSoundEnabled = startSoundEnabled
        self.stopSoundEnabled = stopSoundEnabled
        self.doubleTapFnLockEnabled = doubleTapFnLockEnabled
        self.overlayMeterEnabled = overlayMeterEnabled
        self.silenceThreshold = silenceThreshold
        self.provider = provider
        self.openAIModel = openAIModel
        self.openAIKeyRef = openAIKeyRef
        self.whisperCppPath = whisperCppPath
        self.whisperModelPath = whisperModelPath
        self.language = language
        self.autoInsertEnabled = autoInsertEnabled
        self.clipboardFallbackEnabled = clipboardFallbackEnabled
        self.showCapturedToastEnabled = showCapturedToastEnabled
        self.insertionModePreferred = insertionModePreferred
        self.historyRetentionDays = historyRetentionDays
        self.autoSaveLongCapturesToNotes = autoSaveLongCapturesToNotes
        self.longCaptureThresholdWords = longCaptureThresholdWords
    }
}
