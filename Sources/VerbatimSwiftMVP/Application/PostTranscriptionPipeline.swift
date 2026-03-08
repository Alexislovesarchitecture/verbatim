import Foundation

struct PostTranscriptionPipelineRequest {
    let transcript: Transcript
    let activeAppContextOverride: ActiveAppContext?
    let insertionTarget: InsertionTarget?
    let promptProfiles: [PromptProfile]
    let logicMode: LogicMode
    let logicSettings: LogicSettings
    let refineSettings: RefineSettings
    let interactionSettings: InteractionSettings
    let autoFormatEnabled: Bool
    let canRunAutoFormat: Bool
    let effectiveAPIKey: String?
    let selectedRemoteLogicModelID: String
    let selectedLocalLogicModelID: String
    let forceInsertion: Bool
}

struct ManualReformatRequest {
    let transcript: Transcript
    let activeAppContextOverride: ActiveAppContext?
    let profile: PromptProfile
    let logicMode: LogicMode
    let logicSettings: LogicSettings
    let refineSettings: RefineSettings
    let interactionSettings: InteractionSettings
    let effectiveAPIKey: String?
    let selectedRemoteLogicModelID: String
    let selectedLocalLogicModelID: String
}

struct PostTranscriptionPipelineResult {
    let deterministicResult: DeterministicResult
    let formattedOutput: FormattedOutput?
    let latestLLMResult: LLMResult?
    let pendingActionItemsJSON: String?
    let pendingActionItemsRenderedText: String?
    let lastErrorSummary: String?
}

@MainActor
final class PostTranscriptionPipeline {
    private let transcriptIntentResolver: TranscriptIntentResolverProtocol
    private let deterministicFormatter: DeterministicFormatterServiceProtocol
    private let contextPackBuilder: ContextPackBuilder
    private let activeAppContextService: ActiveAppContextServiceProtocol
    private let transcriptRecordStore: TranscriptRecordStoreProtocol
    private let insertionService: InsertionServiceProtocol
    private let llmFormatterService: LLMFormatterServiceProtocol

    init(
        transcriptIntentResolver: TranscriptIntentResolverProtocol,
        deterministicFormatter: DeterministicFormatterServiceProtocol,
        contextPackBuilder: ContextPackBuilder,
        activeAppContextService: ActiveAppContextServiceProtocol,
        transcriptRecordStore: TranscriptRecordStoreProtocol,
        insertionService: InsertionServiceProtocol,
        llmFormatterService: LLMFormatterServiceProtocol
    ) {
        self.transcriptIntentResolver = transcriptIntentResolver
        self.deterministicFormatter = deterministicFormatter
        self.contextPackBuilder = contextPackBuilder
        self.activeAppContextService = activeAppContextService
        self.transcriptRecordStore = transcriptRecordStore
        self.insertionService = insertionService
        self.llmFormatterService = llmFormatterService
    }

    func processCompletedTranscript(_ request: PostTranscriptionPipelineRequest) async -> PostTranscriptionPipelineResult {
        let activeAppContext = request.activeAppContextOverride ?? activeAppContextService.currentContext()
        let resolvedTranscript = transcriptIntentResolver.resolve(
            transcript: request.transcript,
            selfCorrectionMode: request.logicSettings.selfCorrectionMode,
            glossary: request.refineSettings.glossary,
            activeContext: activeAppContext
        )
        let deterministic = deterministicFormatter.format(
            text: resolvedTranscript.text,
            settings: request.logicSettings,
            glossary: request.refineSettings.glossary
        )

        let contextPack = contextPackBuilder.build(
            activeContext: activeAppContext,
            logicSettings: request.logicSettings,
            refineSettings: request.refineSettings,
            deterministicText: deterministic.text
        )

        var llmResult: LLMResult?
        var lastErrorSummary: String?
        var finalText = deterministic.text
        let selectedProfile = automaticProfile(
            for: activeAppContext.styleCategory,
            settings: request.refineSettings,
            from: request.promptProfiles
        )

        if request.autoFormatEnabled,
           request.canRunAutoFormat,
           request.refineSettings.isEnabled(for: activeAppContext.styleCategory),
           let selectedProfile {
            do {
                let refined = try await llmFormatterService.refine(
                    deterministicText: deterministic.text,
                    contextPack: contextPack,
                    profile: selectedProfile,
                    mode: request.logicMode,
                    modelID: selectedLogicModelID(for: request.logicMode, request: request),
                    apiKey: request.effectiveAPIKey
                )
                llmResult = refined
                finalText = renderedText(from: refined, fallback: deterministic.text)
            } catch {
                lastErrorSummary = error.localizedDescription
            }
        }

        if request.forceInsertion || !request.refineSettings.previewBeforeInsert {
            do {
                try insertionService.insert(
                    text: finalText,
                    autoPaste: request.interactionSettings.autoPasteAfterInsert,
                    target: request.insertionTarget
                )
            } catch {
                lastErrorSummary = error.localizedDescription
            }
        }

        transcriptRecordStore.appendRecord(
            TranscriptRecord(
                createdAt: Date(),
                rawText: request.transcript.rawText,
                deterministicText: deterministic.text,
                llmText: llmResult?.text,
                llmJSON: llmResult?.json,
                llmStatus: llmResult?.status,
                validationStatus: llmResult?.validationStatus,
                profileID: selectedProfile?.id ?? llmResult?.profileID,
                profileVersion: selectedProfile?.version ?? llmResult?.profileVersion,
                modelID: llmResult?.modelID,
                tokens: llmResult?.tokens,
                cachedTokens: llmResult?.cachedTokens,
                latencyMs: llmResult?.latencyMs,
                activeAppName: activeAppContext.appName,
                bundleID: activeAppContext.bundleID,
                styleCategory: activeAppContext.styleCategory
            )
        )

        return PostTranscriptionPipelineResult(
            deterministicResult: deterministic,
            formattedOutput: makeFormattedOutput(
                from: finalText,
                corrections: resolvedTranscript.corrections,
                notes: resolvedTranscript.notes
            ),
            latestLLMResult: llmResult,
            pendingActionItemsJSON: nil,
            pendingActionItemsRenderedText: nil,
            lastErrorSummary: lastErrorSummary
        )
    }

    func runManualReformat(_ request: ManualReformatRequest) async -> PostTranscriptionPipelineResult {
        let activeAppContext = request.activeAppContextOverride ?? activeAppContextService.currentContext()
        let resolvedTranscript = transcriptIntentResolver.resolve(
            transcript: request.transcript,
            selfCorrectionMode: request.logicSettings.selfCorrectionMode,
            glossary: request.refineSettings.glossary,
            activeContext: activeAppContext
        )
        let deterministic = deterministicFormatter.format(
            text: resolvedTranscript.text,
            settings: request.logicSettings,
            glossary: request.refineSettings.glossary
        )

        let contextPack = contextPackBuilder.build(
            activeContext: activeAppContext,
            logicSettings: request.logicSettings,
            refineSettings: request.refineSettings,
            deterministicText: deterministic.text
        )

        do {
            let result = try await llmFormatterService.refine(
                deterministicText: deterministic.text,
                contextPack: contextPack,
                profile: request.profile,
                mode: request.logicMode,
                modelID: selectedLogicModelID(for: request.logicMode, request: request),
                apiKey: request.effectiveAPIKey
            )

            transcriptRecordStore.appendRecord(
                TranscriptRecord(
                    createdAt: Date(),
                    rawText: request.transcript.rawText,
                    deterministicText: deterministic.text,
                    llmText: result.text,
                    llmJSON: result.json,
                    llmStatus: result.status,
                    validationStatus: result.validationStatus,
                    profileID: result.profileID,
                    profileVersion: result.profileVersion,
                    modelID: result.modelID,
                    tokens: result.tokens,
                    cachedTokens: result.cachedTokens,
                    latencyMs: result.latencyMs,
                    activeAppName: activeAppContext.appName,
                    bundleID: activeAppContext.bundleID,
                    styleCategory: activeAppContext.styleCategory
                )
            )

            if request.profile.id == "action_items", let json = result.json {
                return PostTranscriptionPipelineResult(
                    deterministicResult: deterministic,
                    formattedOutput: nil,
                    latestLLMResult: result,
                    pendingActionItemsJSON: json,
                    pendingActionItemsRenderedText: renderedActionItemsText(from: json),
                    lastErrorSummary: nil
                )
            }

            let text = renderedText(from: result, fallback: deterministic.text)
            if !request.refineSettings.previewBeforeInsert {
                try? insertionService.insert(
                    text: text,
                    autoPaste: request.interactionSettings.autoPasteAfterInsert,
                    target: nil
                )
            }

            return PostTranscriptionPipelineResult(
                deterministicResult: deterministic,
                formattedOutput: makeFormattedOutput(
                    from: text,
                    corrections: resolvedTranscript.corrections,
                    notes: resolvedTranscript.notes
                ),
                latestLLMResult: result,
                pendingActionItemsJSON: nil,
                pendingActionItemsRenderedText: nil,
                lastErrorSummary: nil
            )
        } catch {
            return PostTranscriptionPipelineResult(
                deterministicResult: deterministic,
                formattedOutput: makeFormattedOutput(
                    from: deterministic.text,
                    corrections: resolvedTranscript.corrections,
                    notes: resolvedTranscript.notes
                ),
                latestLLMResult: nil,
                pendingActionItemsJSON: nil,
                pendingActionItemsRenderedText: nil,
                lastErrorSummary: error.localizedDescription
            )
        }
    }

    private func automaticProfile(
        for styleCategory: StyleCategory,
        settings: RefineSettings,
        from profiles: [PromptProfile]
    ) -> PromptProfile? {
        let autoProfile = PromptProfile.automaticStyleProfile(for: styleCategory, settings: settings)
        if autoProfile.instructionPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return profiles.first(where: { $0.id == "cleanup" && $0.enabled })
                ?? profiles.first(where: { $0.enabled })
        }
        return autoProfile
    }

    private func renderedText(from result: LLMResult, fallback: String) -> String {
        if let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        if let json = result.json, result.profileID == "action_items" {
            return renderedActionItemsText(from: json)
        }

        return fallback
    }

    private func renderedActionItemsText(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ActionItemsPayload.self, from: data),
              !payload.items.isEmpty else {
            return "No action items."
        }

        return payload.items.enumerated().map { index, item in
            var suffix: [String] = []
            if let owner = item.owner, !owner.isEmpty {
                suffix.append("owner: \(owner)")
            }
            if let dueDate = item.dueDate, !dueDate.isEmpty {
                suffix.append("due: \(dueDate)")
            }
            let detail = suffix.isEmpty ? "" : " (\(suffix.joined(separator: ", ")))"
            return "\(index + 1). \(item.task)\(detail)"
        }.joined(separator: "\n")
    }

    private func makeFormattedOutput(
        from text: String,
        corrections: [ResolvedSelfCorrection],
        notes: [String]
    ) -> FormattedOutput {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let isBulleted = lines.count > 1 && lines.allSatisfy { line in
            line.hasPrefix("•")
                || line.hasPrefix("-")
                || line.hasPrefix("*")
                || line.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }

        let bullets = isBulleted ? lines.map { line in
            line
                .replacingOccurrences(of: #"^[\-\*•]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } : []

        return FormattedOutput(
            clean_text: text,
            format: isBulleted ? "bullets" : "paragraph",
            bullets: bullets,
            self_corrections: corrections.map(\.summary),
            low_confidence_spans: [],
            notes: notes
        )
    }

    private func selectedLogicModelID(for mode: LogicMode, request: PostTranscriptionPipelineRequest) -> String {
        switch mode {
        case .remote:
            return request.selectedRemoteLogicModelID
        case .local:
            return request.selectedLocalLogicModelID
        }
    }

    private func selectedLogicModelID(for mode: LogicMode, request: ManualReformatRequest) -> String {
        switch mode {
        case .remote:
            return request.selectedRemoteLogicModelID
        case .local:
            return request.selectedLocalLogicModelID
        }
    }
}
