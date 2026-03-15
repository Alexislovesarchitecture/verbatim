import Foundation

struct ProviderStateRefreshResult {
    var systemProfile: SystemProfile
    var whisperModelStatuses: [ModelStatus]
    var parakeetModelStatuses: [ModelStatus]
    var appleInstalledLanguages: [LanguageSelection]
    var providerAvailability: [ProviderID: ProviderAvailability]
    var providerReadiness: [ProviderID: ProviderReadiness]
    var providerCapabilities: [ProviderID: CapabilityStatus]
    var featureCapabilities: [FeatureID: CapabilityStatus]
    var selectionResolution: SharedCoreSelectionResolution
    var modelSelectionResolution: ProviderModelSelectionResolution
    var providerDiagnostics: [ProviderDiagnosticStatus]
    var providerDiagnosticSummaryLines: [ProviderID: String]
}

enum ProviderStateCoordinator {
    static func refresh(
        settings: AppSettings,
        systemProfile: SystemProfile,
        capabilityManifest: CapabilityManifest,
        providerFallbackOrder: [ProviderID],
        sharedCore: SharedCoreBridgeProtocol,
        providers: [ProviderID: any TranscriptionProvider],
        appleProvider: AppleSpeechProvider,
        whisperModelManager: WhisperModelManager,
        parakeetModelManager: ParakeetModelManager,
        whisperRuntimeManager: WhisperRuntimeManager,
        parakeetRuntimeManager: ParakeetRuntimeManager
    ) async -> ProviderStateRefreshResult {
        var availability: [ProviderID: ProviderAvailability] = [:]
        var readiness: [ProviderID: ProviderReadiness] = [:]

        for (providerID, provider) in providers {
            availability[providerID] = await provider.availability()
            readiness[providerID] = await provider.readiness(for: settings.preferredLanguage(for: providerID))
        }

        let installedLanguages = await appleProvider.installedLanguages()
        let capabilityResolution = sharedCore.resolveCapabilities(
            manifest: capabilityManifest,
            profile: systemProfile,
            storedProvider: settings.selectedProvider,
            fallbackOrder: providerFallbackOrder,
            availability: availability,
            readiness: readiness
        )
        let selectionResolution = sharedCore.resolveSelection(
            storedProvider: settings.selectedProvider,
            fallbackOrder: providerFallbackOrder,
            capabilities: capabilityResolution.providerCapabilities,
            preferredLanguages: settings.preferredLanguages,
            appleInstalledLanguages: installedLanguages
        )

        let whisperStatuses = await whisperModelManager.statuses()
        let parakeetStatuses = await parakeetModelManager.statuses()
        let modelSelectionResolution = sharedCore.resolveProviderModelSelection(
            selectedProvider: settings.selectedProvider,
            selectedWhisperModelID: settings.selectedWhisperModelID,
            selectedParakeetModelID: settings.selectedParakeetModelID,
            whisperStatuses: whisperStatuses.map {
                ProviderModelStatusInput(
                    id: $0.descriptor.id,
                    name: $0.descriptor.name,
                    supportedLanguageIDs: $0.descriptor.supportedLanguageIDs,
                    isInstalled: $0.state == .ready
                )
            },
            parakeetStatuses: parakeetStatuses.map {
                ProviderModelStatusInput(
                    id: $0.descriptor.id,
                    name: $0.descriptor.name,
                    supportedLanguageIDs: $0.descriptor.supportedLanguageIDs,
                    isInstalled: $0.state == .ready
                )
            },
            appleInstalledLanguages: installedLanguages
        )

        let whisperSnapshot = await whisperRuntimeManager.snapshot()
        let parakeetSnapshot = await parakeetRuntimeManager.snapshot()
        let reductions = Dictionary(uniqueKeysWithValues: sharedCore.reduceProviderDiagnostics([
            ProviderDiagnosticInput(
                provider: .whisper,
                capability: capabilityResolution.providerCapabilities[.whisper] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.whisper] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.whisper] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                runtimeStateLabel: whisperSnapshot.state.rawValue.capitalized,
                runtimeError: whisperSnapshot.lastError
            ),
            ProviderDiagnosticInput(
                provider: .parakeet,
                capability: capabilityResolution.providerCapabilities[.parakeet] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.parakeet] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.parakeet] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                runtimeStateLabel: parakeetSnapshot.state.rawValue.capitalized,
                runtimeError: parakeetSnapshot.lastError
            ),
            ProviderDiagnosticInput(
                provider: .appleSpeech,
                capability: capabilityResolution.providerCapabilities[.appleSpeech] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.appleSpeech] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.appleSpeech] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                runtimeStateLabel: nil,
                runtimeError: nil
            ),
        ]).map { ($0.provider, $0) })

        let providerDiagnostics = ProviderDiagnosticsCoordinator.build(
            settings: settings,
            capabilities: capabilityResolution.providerCapabilities,
            availability: availability,
            readiness: readiness,
            appleLanguages: installedLanguages,
            selectedWhisperDescription: modelSelectionResolution.selectedWhisperDescription,
            selectedWhisperInstalled: modelSelectionResolution.selectedWhisperInstalled,
            selectedParakeetDescription: modelSelectionResolution.selectedParakeetDescription,
            selectedParakeetInstalled: modelSelectionResolution.selectedParakeetInstalled,
            whisperSnapshot: whisperSnapshot,
            parakeetSnapshot: parakeetSnapshot,
            whisperInstallSource: await whisperModelManager.installSource(for: settings.selectedWhisperModelID),
            parakeetInstallSource: await parakeetModelManager.installSource(for: settings.selectedParakeetModelID),
            reductions: reductions
        )

        return ProviderStateRefreshResult(
            systemProfile: systemProfile,
            whisperModelStatuses: whisperStatuses,
            parakeetModelStatuses: parakeetStatuses,
            appleInstalledLanguages: installedLanguages,
            providerAvailability: availability,
            providerReadiness: readiness,
            providerCapabilities: capabilityResolution.providerCapabilities,
            featureCapabilities: capabilityResolution.featureCapabilities,
            selectionResolution: selectionResolution,
            modelSelectionResolution: modelSelectionResolution,
            providerDiagnostics: providerDiagnostics,
            providerDiagnosticSummaryLines: Dictionary(uniqueKeysWithValues: reductions.map { ($0.key, $0.value.summaryLine) })
        )
    }
}
