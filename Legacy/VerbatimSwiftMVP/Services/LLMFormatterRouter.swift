import Foundation

@MainActor
final class LLMFormatterRouter: LLMFormatterServiceProtocol {
    private let remoteService: OpenAIRemoteRefineServiceProtocol
    private let localService: LocalLLMRefineServiceProtocol
    private let recordStore: TranscriptRecordStoreProtocol

    init(
        remoteService: OpenAIRemoteRefineServiceProtocol,
        localService: LocalLLMRefineServiceProtocol,
        recordStore: TranscriptRecordStoreProtocol
    ) {
        self.remoteService = remoteService
        self.localService = localService
        self.recordStore = recordStore
    }

    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        mode: LogicMode,
        modelID: String,
        apiKey: String?
    ) async throws -> LLMResult {
        if !profile.enabled {
            return LLMResult(
                text: deterministicText,
                json: nil,
                status: .fallback,
                validationStatus: .notApplicable,
                tokens: 0,
                cachedTokens: 0,
                latencyMs: 0,
                profileID: profile.id,
                profileVersion: profile.version,
                modelID: modelID,
                fromCache: false
            )
        }

        let cacheKey = recordStore.makeCacheKey(
            profile: profile,
            modelID: modelID,
            contextPack: contextPack,
            deterministicText: deterministicText
        )

        if let cached = recordStore.fetchCachedResult(for: cacheKey) {
            return cached
        }

        let result: LLMResult
        switch mode {
        case .remote:
            result = try await remoteService.refine(
                deterministicText: deterministicText,
                contextPack: contextPack,
                profile: profile,
                apiKey: apiKey,
                modelID: modelID
            )
        case .local:
            result = try await localService.refine(
                deterministicText: deterministicText,
                contextPack: contextPack,
                profile: profile,
                modelID: modelID
            )
        }

        recordStore.saveCachedResult(result, for: cacheKey)
        return result
    }
}
