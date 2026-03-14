import XCTest
@testable import Verbatim

final class CapabilityMatrixTests: XCTestCase {
    private let matrix = CapabilityMatrix(manifest: CapabilityManifestRepository.load())

    func testAppleSpeechIsUnsupportedOnWindowsProfile() {
        let profile = SystemProfile(
            osFamily: .windows,
            osVersion: SystemVersionInfo(major: 11, minor: 0, patch: 0),
            architecture: .x86_64,
            accelerator: .none
        )

        let status = matrix.providerCapability(
            for: .appleSpeech,
            profile: profile,
            availability: ProviderAvailability(isAvailable: false, reason: "Unavailable"),
            readiness: ProviderReadiness(kind: .unavailable, message: "Unavailable", actionTitle: nil)
        )

        XCTAssertEqual(status.kind, .unsupported)
    }

    func testWhisperSupportedButNotReadyUsesReadinessAction() {
        let profile = SystemProfile(
            osFamily: .macOS,
            osVersion: SystemVersionInfo(major: 26, minor: 0, patch: 0),
            architecture: .arm64,
            accelerator: .appleSilicon
        )

        let status = matrix.providerCapability(
            for: .whisper,
            profile: profile,
            availability: ProviderAvailability(isAvailable: true, reason: nil),
            readiness: ProviderReadiness(kind: .missingModel, message: "Download the selected Whisper model first.", actionTitle: "Download")
        )

        XCTAssertEqual(status.kind, .supportedButNotReady)
        XCTAssertEqual(status.actionTitle, "Download")
    }

    func testParakeetUnsupportedWithoutWindowsNVIDIAProfile() {
        let profile = SystemProfile(
            osFamily: .macOS,
            osVersion: SystemVersionInfo(major: 26, minor: 0, patch: 0),
            architecture: .arm64,
            accelerator: .appleSilicon
        )

        let status = matrix.providerCapability(
            for: .parakeet,
            profile: profile,
            availability: ProviderAvailability(isAvailable: true, reason: nil),
            readiness: .ready
        )

        XCTAssertEqual(status.kind, .unsupported)
    }

    func testEffectiveProviderFallsBackToFirstAvailableProvider() {
        let capabilities: [ProviderID: CapabilityStatus] = [
            .parakeet: CapabilityStatus(kind: .unsupported, reason: "Unsupported", actionTitle: nil),
            .whisper: .available,
            .appleSpeech: .available,
        ]

        let effective = matrix.effectiveProvider(
            storedProvider: .parakeet,
            capabilities: capabilities,
            fallbackOrder: [.whisper, .appleSpeech, .parakeet]
        )

        XCTAssertEqual(effective, .whisper)
    }
}
