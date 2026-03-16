import Foundation

struct DictationSessionStartResult {
    var activeContext: ActiveAppContext
    var styleDecision: StyleDecisionReport
}

enum DictationSessionCoordinator {
    @MainActor
    static func ensureMicrophoneAccess(with permissionsManager: PermissionsManager) async -> Bool {
        if permissionsManager.microphoneAuthorized {
            return true
        }
        return await permissionsManager.requestMicrophone()
    }

    @MainActor
    static func start(
        provider: ProviderID,
        settings: AppSettings,
        activeAppContextService: ActiveAppContextServiceProtocol,
        sharedCore: SharedCoreBridgeProtocol,
        coordinator: TranscriptionCoordinator
    ) async throws -> DictationSessionStartResult {
        let activeContext = activeAppContextService.currentContext()
        let styleDecision = sharedCore.resolveStyleDecision(context: activeContext, settings: settings.styleSettings)
        try await coordinator.startRecording(provider: provider, activeContext: activeContext, styleDecision: styleDecision)
        return DictationSessionStartResult(activeContext: activeContext, styleDecision: styleDecision)
    }

    @MainActor
    static func stop(
        provider: ProviderID,
        language: LanguageSelection,
        dictionaryEntries: [DictionaryEntry],
        accessibilityGranted: Bool,
        coordinator: TranscriptionCoordinator
    ) async throws -> CoordinatorOutcome {
        try await coordinator.stopRecordingAndTranscribe(
            provider: provider,
            language: language,
            dictionaryEntries: dictionaryEntries,
            accessibilityGranted: accessibilityGranted
        )
    }
}
