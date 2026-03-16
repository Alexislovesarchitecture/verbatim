import XCTest
@testable import Verbatim

final class SharedCoreBridgeTests: XCTestCase {
    func testTriggerModeDecodesLegacyStorageValuesAndEncodesSemanticValues() throws {
        let decoder = JSONDecoder()
        let legacyHold = try decoder.decode(TriggerMode.self, from: Data(#""hold_to_talk""#.utf8))
        let legacyToggle = try decoder.decode(TriggerMode.self, from: Data(#""tap_to_toggle""#.utf8))

        XCTAssertEqual(legacyHold, .hold)
        XCTAssertEqual(legacyToggle, .toggle)
        XCTAssertEqual(String(data: try JSONEncoder().encode(TriggerMode.hold), encoding: .utf8), #""hold""#)
        XCTAssertEqual(String(data: try JSONEncoder().encode(TriggerMode.toggle), encoding: .utf8), #""toggle""#)
    }

    func testFocusedFieldEmailCueResolvesEmailDecision() {
        let bridge = SharedCoreBridge(forceFallback: true)
        let context = ActiveAppContext(
            appName: "Atlas",
            bundleID: "com.openai.atlas",
            processIdentifier: 7,
            styleCategory: .other,
            windowTitle: "Compose - Outlook",
            focusedElementRole: "AXTextField",
            focusedElementSubrole: nil,
            focusedElementTitle: "Subject",
            focusedElementPlaceholder: nil,
            focusedElementDescription: nil,
            focusedValueSnippet: nil
        )

        let decision = bridge.resolveStyleDecision(context: context, settings: .init())

        XCTAssertEqual(decision.category, .email)
        XCTAssertEqual(decision.source, .focusedField)
    }

    func testDoubleTapLockStartsOnSecondTap() {
        let bridge = SharedCoreBridge(forceFallback: true)
        bridge.prepareTrigger(mode: .doubleTapLock)

        let first = bridge.handleInputEvent(.triggerDown, isRecording: false, timestamp: Date(timeIntervalSince1970: 10))
        let second = bridge.handleInputEvent(.triggerDown, isRecording: false, timestamp: Date(timeIntervalSince1970: 10.2))

        XCTAssertEqual(first, .none)
        XCTAssertEqual(second, .startRecording)
    }

    func testConservativeFormattingPreservesWording() {
        let bridge = SharedCoreBridge(forceFallback: true)
        var settings = StyleSettings()
        settings.setEnabled(true, for: .workMessages)
        settings.setPreset(.formal, for: .workMessages)
        let context = ActiveAppContext(
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            processIdentifier: 7,
            styleCategory: .workMessages,
            windowTitle: "Team thread",
            focusedElementRole: "AXTextField",
            focusedElementSubrole: nil,
            focusedElementTitle: "Reply",
            focusedElementPlaceholder: nil,
            focusedElementDescription: nil,
            focusedValueSnippet: nil
        )
        let decision = bridge.resolveStyleDecision(context: context, settings: settings)

        let processed = bridge.processTranscript(
            text: "um hello there",
            context: context,
            settings: settings,
            resolvedDecision: decision,
            dictionaryEntries: []
        )

        XCTAssertEqual(processed.cleanedText, "hello there")
        XCTAssertEqual(processed.finalText, "Hello there.")
    }

    func testDictionaryCorrectionRewritesHintToCanonicalPhrase() {
        let bridge = SharedCoreBridge(forceFallback: true)

        let processed = bridge.processTranscript(
            text: "betty is here listening",
            context: nil,
            settings: .init(),
            resolvedDecision: nil,
            dictionaryEntries: [DictionaryEntry(phrase: "Batty", hint: "Betty")]
        )

        XCTAssertEqual(processed.cleanedText, "Batty is here listening")
        XCTAssertEqual(processed.finalText, "Batty is here listening")
    }

    func testDictionaryCorrectionRewritesSpelledSequenceToCanonicalPhrase() {
        let bridge = SharedCoreBridge(forceFallback: true)

        let processed = bridge.processTranscript(
            text: "B-A-T-T-Y is here",
            context: nil,
            settings: .init(),
            resolvedDecision: nil,
            dictionaryEntries: [DictionaryEntry(phrase: "Batty")]
        )

        XCTAssertEqual(processed.cleanedText, "Batty is here")
        XCTAssertEqual(processed.finalText, "Batty is here")
    }

    func testSelectionResolutionFallsBackAndNormalizesProviderLanguages() {
        let bridge = SharedCoreBridge(forceFallback: true)
        let capabilities: [ProviderID: CapabilityStatus] = [
            .appleSpeech: CapabilityStatus(kind: .unsupported, reason: "Apple Speech is unavailable on this system.", actionTitle: nil),
            .whisper: .available,
            .parakeet: CapabilityStatus(kind: .unsupported, reason: "Parakeet currently requires Windows with an NVIDIA CUDA-compatible system.", actionTitle: nil),
        ]

        let resolution = bridge.resolveSelection(
            storedProvider: .appleSpeech,
            fallbackOrder: [.whisper, .appleSpeech, .parakeet],
            capabilities: capabilities,
            preferredLanguages: ProviderLanguageSettings(
                appleSpeechID: LanguageSelection.auto.identifier,
                whisperID: "es-ES",
                parakeetID: "ru-RU"
            ),
            appleInstalledLanguages: [LanguageSelection(identifier: "fr-FR")]
        )

        XCTAssertEqual(resolution.effectiveProvider, .whisper)
        XCTAssertEqual(resolution.effectiveLanguages.appleSpeechID, "en-US")
        XCTAssertEqual(resolution.effectiveLanguages.whisperID, "es-ES")
        XCTAssertEqual(resolution.effectiveLanguages.parakeetID, LanguageSelection.auto.identifier)
        XCTAssertEqual(
            resolution.effectiveProviderMessage,
            "Apple Speech is unavailable on this system. Verbatim will use Whisper while this preference is unavailable."
        )
    }

    func testProviderModelSelectionOptionsMatchProviderPolicies() {
        let bridge = SharedCoreBridge(forceFallback: true)

        let whisper = bridge.resolveProviderModelSelection(
            selectedProvider: .whisper,
            selectedWhisperModelID: "base",
            selectedParakeetModelID: "parakeet",
            whisperStatuses: [],
            parakeetStatuses: [],
            appleInstalledLanguages: []
        )
        XCTAssertTrue(whisper.currentLanguageOptions.contains(.auto))
        XCTAssertTrue(whisper.currentLanguageOptions.contains(LanguageSelection(identifier: "pt-BR")))
        XCTAssertTrue(whisper.currentLanguageOptions.contains(LanguageSelection(identifier: "ru-RU")))

        let apple = bridge.resolveProviderModelSelection(
            selectedProvider: .appleSpeech,
            selectedWhisperModelID: "base",
            selectedParakeetModelID: "parakeet",
            whisperStatuses: [],
            parakeetStatuses: [],
            appleInstalledLanguages: [LanguageSelection(identifier: "en-US")]
        )
        XCTAssertFalse(apple.currentLanguageOptions.contains(.auto))
        XCTAssertEqual(apple.currentLanguageOptions, [LanguageSelection(identifier: "en-US")])

        let parakeet = bridge.resolveProviderModelSelection(
            selectedProvider: .parakeet,
            selectedWhisperModelID: "base",
            selectedParakeetModelID: "parakeet",
            whisperStatuses: [],
            parakeetStatuses: [
                ProviderModelStatusInput(
                    id: "parakeet",
                    name: "Parakeet",
                    supportedLanguageIDs: ["en-US", "es-ES"],
                    isInstalled: true
                )
            ],
            appleInstalledLanguages: []
        )
        XCTAssertEqual(parakeet.currentLanguageOptions, [.auto])
    }
}
