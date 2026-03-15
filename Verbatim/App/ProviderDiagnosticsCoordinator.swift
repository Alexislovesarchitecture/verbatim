import Foundation

enum ProviderDiagnosticsCoordinator {
    static func build(
        settings: AppSettings,
        capabilities: [ProviderID: CapabilityStatus],
        availability: [ProviderID: ProviderAvailability],
        readiness: [ProviderID: ProviderReadiness],
        appleLanguages: [LanguageSelection],
        selectedWhisperDescription: String,
        selectedWhisperInstalled: Bool,
        selectedParakeetDescription: String,
        selectedParakeetInstalled: Bool,
        whisperSnapshot: RuntimeHealthSnapshot,
        parakeetSnapshot: RuntimeHealthSnapshot,
        whisperInstallSource: InstalledAssetSource?,
        parakeetInstallSource: InstalledAssetSource?,
        reductions: [ProviderID: ProviderDiagnosticReduction]
    ) -> [ProviderDiagnosticStatus] {
        [
            ProviderDiagnosticStatus(
                provider: .whisper,
                capability: capabilities[.whisper] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.whisper] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.whisper] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: selectedWhisperDescription,
                selectionInstalled: selectedWhisperInstalled,
                selectionSource: whisperInstallSource,
                runtimeSnapshot: whisperSnapshot,
                lastCheck: whisperSnapshot.lastCheck ?? .now,
                lastError: reductions[.whisper]?.lastError
            ),
            ProviderDiagnosticStatus(
                provider: .parakeet,
                capability: capabilities[.parakeet] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.parakeet] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.parakeet] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: selectedParakeetDescription,
                selectionInstalled: selectedParakeetInstalled,
                selectionSource: parakeetInstallSource,
                runtimeSnapshot: parakeetSnapshot,
                lastCheck: parakeetSnapshot.lastCheck ?? .now,
                lastError: reductions[.parakeet]?.lastError
            ),
            ProviderDiagnosticStatus(
                provider: .appleSpeech,
                capability: capabilities[.appleSpeech] ?? CapabilityStatus(kind: .supportedButNotReady, reason: "Checking capability state…", actionTitle: nil),
                availability: availability[.appleSpeech] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.appleSpeech] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: settings.preferredLanguage(for: .appleSpeech).title,
                selectionInstalled: settings.preferredLanguage(for: .appleSpeech).isAuto == false && appleLanguages.contains(settings.preferredLanguage(for: .appleSpeech)),
                selectionSource: nil,
                runtimeSnapshot: nil,
                lastCheck: .now,
                lastError: reductions[.appleSpeech]?.lastError
            ),
        ]
    }
}
