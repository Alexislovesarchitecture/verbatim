import Foundation

struct CapabilityMatrix {
    let manifest: CapabilityManifest

    func providerCapability(
        for provider: ProviderID,
        profile: SystemProfile,
        availability: ProviderAvailability,
        readiness: ProviderReadiness
    ) -> CapabilityStatus {
        guard let descriptor = manifest.providers.first(where: { $0.provider == provider }) else {
            if availability.isAvailable, readiness.isReady {
                return .available
            }
            return CapabilityStatus(
                kind: .supportedButNotReady,
                reason: readiness.message.isEmpty ? availability.reason : readiness.message,
                actionTitle: readiness.actionTitle
            )
        }

        guard descriptor.requirements.supports(profile) else {
            return CapabilityStatus(kind: .unsupported, reason: descriptor.unsupportedReason, actionTitle: nil)
        }

        guard availability.isAvailable else {
            return CapabilityStatus(
                kind: .supportedButNotReady,
                reason: availability.reason ?? "\(provider.title) is not ready on this system.",
                actionTitle: nil
            )
        }

        guard readiness.isReady else {
            return CapabilityStatus(
                kind: .supportedButNotReady,
                reason: readiness.message,
                actionTitle: readiness.actionTitle
            )
        }

        return .available
    }

    func featureCapability(for feature: FeatureID, profile: SystemProfile) -> CapabilityStatus {
        guard let descriptor = manifest.features.first(where: { $0.feature == feature }) else {
            return .available
        }

        guard descriptor.requirements.supports(profile) else {
            return CapabilityStatus(kind: .unsupported, reason: descriptor.unsupportedReason, actionTitle: nil)
        }

        return .available
    }

    func effectiveProvider(
        storedProvider: ProviderID,
        capabilities: [ProviderID: CapabilityStatus],
        fallbackOrder: [ProviderID]
    ) -> ProviderID {
        if capabilities[storedProvider]?.isSupported == true {
            return storedProvider
        }

        if let availableFallback = fallbackOrder.first(where: { capabilities[$0]?.isAvailable == true }) {
            return availableFallback
        }

        if let supportedFallback = fallbackOrder.first(where: { capabilities[$0]?.isSupported == true }) {
            return supportedFallback
        }

        return storedProvider
    }
}
