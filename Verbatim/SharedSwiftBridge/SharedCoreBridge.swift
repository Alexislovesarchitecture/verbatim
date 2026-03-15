import Foundation
import Darwin

protocol SharedCoreBridgeProtocol: AnyObject {
    func prepareTrigger(mode: TriggerMode)
    func resolveCapabilities(
        manifest: CapabilityManifest,
        profile: SystemProfile,
        storedProvider: ProviderID,
        fallbackOrder: [ProviderID],
        availability: [ProviderID: ProviderAvailability],
        readiness: [ProviderID: ProviderReadiness]
    ) -> SharedCoreCapabilityResolution
    func summarizeTriggerState(
        mode: TriggerMode,
        startResult: HotkeyStartResult
    ) -> TriggerStateSummary
    func handleInputEvent(
        _ event: InputEvent,
        isRecording: Bool,
        timestamp: Date
    ) -> DictationAction
    func resolveStyleDecision(
        context: ActiveAppContext,
        settings: StyleSettings
    ) -> StyleDecisionReport
    func processTranscript(
        text: String,
        context: ActiveAppContext?,
        settings: StyleSettings,
        resolvedDecision: StyleDecisionReport?
    ) -> SharedCoreProcessedTranscript
}

struct SharedCoreProcessedTranscript: Equatable, Sendable {
    var cleanedText: String
    var finalText: String
    var changed: Bool
    var decision: StyleDecisionReport
}

final class SharedCoreBridge: SharedCoreBridgeProtocol {
    private struct Envelope<Value: Decodable>: Decodable {
        let ok: Bool
        let value: Value?
        let error: String?
    }

    private struct EmptyResponse: Decodable {}

    private struct CapabilityResolutionRequest: Encodable {
        let manifest: CapabilityManifest
        let profile: SystemProfile
        let storedProvider: ProviderID
        let fallbackOrder: [ProviderID]
        let availability: [ProviderID: ProviderAvailability]
        let readiness: [ProviderID: ProviderReadiness]
    }

    private struct SummarizeHotkeyStartResponse: Decodable {
        let statusMessage: String
        let effectiveTriggerLabel: String
        let backendLabel: String
        let fallbackReason: String?
        let isAvailable: Bool
    }

    private struct InputEventResponse: Decodable {
        let action: String
    }

    private struct StyleDecisionPayload: Codable {
        let category: StyleCategory
        let preset: StylePreset
        let source: StyleDecisionSource
        let confidence: Double
        let formattingEnabled: Bool
        let reason: String?
        let outputPreview: String?
    }

    private struct ProcessTranscriptResponse: Decodable {
        let cleanedText: String
        let finalText: String
        let changed: Bool
        let decision: StyleDecisionPayload
    }

    private struct PrepareTriggerRequest: Encodable {
        let mode: TriggerMode
    }

    private struct SummarizeTriggerStateRequest: Encodable {
        let mode: TriggerMode
        let startResult: HotkeyStartResultPayload
    }

    private struct HotkeyStartResultPayload: Encodable {
        let backend: HotkeyBackend
        let effectiveTriggerLabel: String
        let originalTriggerLabel: String
        let fallbackWasUsed: Bool
        let message: String?
        let recommendedFallbackLabel: String?
        let permissionGranted: Bool
        let isActive: Bool

        init(_ result: HotkeyStartResult) {
            backend = result.backend
            effectiveTriggerLabel = result.effectiveBinding.displayTitle
            originalTriggerLabel = result.originalBinding.displayTitle
            fallbackWasUsed = result.fallbackWasUsed
            message = result.message
            recommendedFallbackLabel = result.recommendedFallback?.displayTitle
            permissionGranted = result.permissionGranted
            isActive = result.isActive
        }
    }

    private struct HandleInputEventRequest: Encodable {
        let event: InputEvent
        let isRecording: Bool
        let timestampMs: Int64
    }

    private struct ResolveStyleContextRequest: Encodable {
        let context: ActiveAppContext
        let settings: StyleSettings
    }

    private struct ProcessTranscriptRequest: Encodable {
        let text: String
        let context: ActiveAppContext?
        let settings: StyleSettings
        let resolvedDecision: StyleDecisionPayload?
    }

    private typealias EngineNew = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias EngineFree = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CoreVersion = @convention(c) () -> UnsafePointer<CChar>?
    private typealias JSONCall = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias FreeString = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let forceFallback: Bool
    private let fallback = SharedCoreFallback()
    private var libraryHandle: UnsafeMutableRawPointer?
    private var engineHandle: UnsafeMutableRawPointer?
    private var engineFree: EngineFree?
    private var freeString: FreeString?
    private var prepareTriggerFunction: JSONCall?
    private var resolveCapabilitiesFunction: JSONCall?
    private var summarizeTriggerStateFunction: JSONCall?
    private var handleInputEventFunction: JSONCall?
    private var resolveStyleContextFunction: JSONCall?
    private var processTranscriptFunction: JSONCall?

    init(forceFallback: Bool = false) {
        self.forceFallback = forceFallback
        guard forceFallback == false else { return }
        loadLibraryIfAvailable()
    }

    deinit {
        if let engineFree {
            engineFree(engineHandle)
        }
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    func prepareTrigger(mode: TriggerMode) {
        let request = PrepareTriggerRequest(mode: mode)
        if call(function: prepareTriggerFunction, request: request, decode: EmptyResponse.self) == nil {
            fallback.prepareTrigger(mode: mode)
        }
    }

    func resolveCapabilities(
        manifest: CapabilityManifest,
        profile: SystemProfile,
        storedProvider: ProviderID,
        fallbackOrder: [ProviderID],
        availability: [ProviderID: ProviderAvailability],
        readiness: [ProviderID: ProviderReadiness]
    ) -> SharedCoreCapabilityResolution {
        guard let response: SharedCoreCapabilityResolution = call(
            function: resolveCapabilitiesFunction,
            request: CapabilityResolutionRequest(
                manifest: manifest,
                profile: profile,
                storedProvider: storedProvider,
                fallbackOrder: fallbackOrder,
                availability: availability,
                readiness: readiness
            ),
            decode: SharedCoreCapabilityResolution.self
        ) else {
            return fallback.resolveCapabilities(
                manifest: manifest,
                profile: profile,
                storedProvider: storedProvider,
                fallbackOrder: fallbackOrder,
                availability: availability,
                readiness: readiness
            )
        }
        return response
    }

    func summarizeTriggerState(mode: TriggerMode, startResult: HotkeyStartResult) -> TriggerStateSummary {
        guard let response: SummarizeHotkeyStartResponse = call(
            function: summarizeTriggerStateFunction,
            request: SummarizeTriggerStateRequest(mode: mode, startResult: HotkeyStartResultPayload(startResult)),
            decode: SummarizeHotkeyStartResponse.self
        ) else {
            return fallback.summarizeTriggerState(mode: mode, startResult: startResult)
        }
        return TriggerStateSummary(
            statusMessage: response.statusMessage,
            effectiveTriggerLabel: response.effectiveTriggerLabel,
            backendLabel: response.backendLabel,
            fallbackReason: response.fallbackReason,
            isAvailable: response.isAvailable
        )
    }

    func handleInputEvent(_ event: InputEvent, isRecording: Bool, timestamp: Date) -> DictationAction {
        let request = HandleInputEventRequest(event: event, isRecording: isRecording, timestampMs: Int64(timestamp.timeIntervalSince1970 * 1000))
        guard let response: InputEventResponse = call(function: handleInputEventFunction, request: request, decode: InputEventResponse.self),
              let action = DictationAction(rawValue: response.action) else {
            return fallback.handleInputEvent(event, isRecording: isRecording, timestamp: timestamp)
        }
        return action
    }

    func resolveStyleDecision(context: ActiveAppContext, settings: StyleSettings) -> StyleDecisionReport {
        guard let response: StyleDecisionPayload = call(
            function: resolveStyleContextFunction,
            request: ResolveStyleContextRequest(context: context, settings: settings),
            decode: StyleDecisionPayload.self
        ) else {
            return fallback.resolveStyleDecision(context: context, settings: settings)
        }
        return mapDecisionPayload(response)
    }

    func processTranscript(text: String, context: ActiveAppContext?, settings: StyleSettings, resolvedDecision: StyleDecisionReport?) -> SharedCoreProcessedTranscript {
        let request = ProcessTranscriptRequest(
            text: text,
            context: context,
            settings: settings,
            resolvedDecision: resolvedDecision.map(payload(from:))
        )
        guard let response: ProcessTranscriptResponse = call(
            function: processTranscriptFunction,
            request: request,
            decode: ProcessTranscriptResponse.self
        ) else {
            return fallback.processTranscript(text: text, context: context, settings: settings, resolvedDecision: resolvedDecision)
        }
        return SharedCoreProcessedTranscript(
            cleanedText: response.cleanedText,
            finalText: response.finalText,
            changed: response.changed,
            decision: mapDecisionPayload(response.decision)
        )
    }

    private func loadLibraryIfAvailable() {
        for url in candidateLibraryURLs() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { continue }
            libraryHandle = handle
            engineFree = resolveSymbol(named: "verbatim_core_engine_free", in: handle, as: EngineFree.self)
            freeString = resolveSymbol(named: "verbatim_core_free_string", in: handle, as: FreeString.self)
            prepareTriggerFunction = resolveSymbol(named: "verbatim_core_prepare_trigger", in: handle, as: JSONCall.self)
            resolveCapabilitiesFunction = resolveSymbol(named: "verbatim_core_resolve_capabilities", in: handle, as: JSONCall.self)
            summarizeTriggerStateFunction = resolveSymbol(named: "verbatim_core_summarize_trigger_state", in: handle, as: JSONCall.self)
            handleInputEventFunction = resolveSymbol(named: "verbatim_core_handle_input_event", in: handle, as: JSONCall.self)
            resolveStyleContextFunction = resolveSymbol(named: "verbatim_core_resolve_style_context", in: handle, as: JSONCall.self)
            processTranscriptFunction = resolveSymbol(named: "verbatim_core_process_transcript", in: handle, as: JSONCall.self)
            let engineNew = resolveSymbol(named: "verbatim_core_engine_new", in: handle, as: EngineNew.self)
            let version = resolveSymbol(named: "verbatim_core_version", in: handle, as: CoreVersion.self)
            if let version, let value = version() {
                let versionString = String(cString: value)
                if versionString.isEmpty == false {
                    _ = versionString
                }
            }
            engineHandle = engineNew?()
            if engineHandle != nil,
               prepareTriggerFunction != nil,
               resolveCapabilitiesFunction != nil,
               summarizeTriggerStateFunction != nil,
               handleInputEventFunction != nil,
               resolveStyleContextFunction != nil,
               processTranscriptFunction != nil,
               freeString != nil {
                return
            }
            if let engineFree {
                engineFree(engineHandle)
            }
            engineHandle = nil
            dlclose(handle)
            libraryHandle = nil
        }
    }

    private func candidateLibraryURLs() -> [URL] {
        var urls: [URL] = []
        if let override = ProcessInfo.processInfo.environment["VERBATIM_RUST_CORE_DYLIB"], override.isEmpty == false {
            urls.append(URL(fileURLWithPath: override))
        }
        if let resourceURL = Bundle.module.resourceURL {
            urls.append(resourceURL.appendingPathComponent("RustRuntime/libverbatim_core.dylib"))
        }
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(repoRoot.appendingPathComponent("Verbatim/RustRuntime/libverbatim_core.dylib"))
        urls.append(repoRoot.appendingPathComponent("RustCore/target/debug/libverbatim_core.dylib"))
        urls.append(repoRoot.appendingPathComponent("RustCore/target/release/libverbatim_core.dylib"))
        return urls
    }

    private func call<Request: Encodable, Response: Decodable>(
        function: JSONCall?,
        request: Request,
        decode: Response.Type
    ) -> Response? {
        guard let function,
              let engineHandle,
              let freeString,
              let requestData = try? JSONEncoder().encode(request),
              let requestCString = String(data: requestData, encoding: .utf8) else {
            return nil
        }
        let resultPointer = requestCString.withCString { function(engineHandle, $0) }
        guard let resultPointer else { return nil }
        defer { freeString(resultPointer) }
        let rawJSON = String(cString: resultPointer)
        guard let data = rawJSON.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope<Response>.self, from: data),
              envelope.ok,
              let value = envelope.value else {
            return nil
        }
        return value
    }

    private func resolveSymbol<T>(named name: String, in handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private func payload(from report: StyleDecisionReport) -> StyleDecisionPayload {
        StyleDecisionPayload(
            category: report.category,
            preset: report.preset,
            source: report.source,
            confidence: report.confidence,
            formattingEnabled: report.formattingEnabled,
            reason: report.reason,
            outputPreview: report.outputPreview
        )
    }

    private func mapDecisionPayload(_ payload: StyleDecisionPayload) -> StyleDecisionReport {
        StyleDecisionReport(
            timestamp: .now,
            category: payload.category,
            preset: payload.preset,
            source: payload.source,
            confidence: payload.confidence,
            formattingEnabled: payload.formattingEnabled,
            reason: payload.reason,
            outputPreview: payload.outputPreview
        )
    }
}

private final class SharedCoreFallback {
    private var currentTriggerMode: TriggerMode = .hold
    private var hotkeyIsPressed = false
    private var lastTapAt: Date?

    func prepareTrigger(mode: TriggerMode) {
        currentTriggerMode = mode
        hotkeyIsPressed = false
        lastTapAt = nil
    }

    func resolveCapabilities(
        manifest: CapabilityManifest,
        profile: SystemProfile,
        storedProvider: ProviderID,
        fallbackOrder: [ProviderID],
        availability: [ProviderID: ProviderAvailability],
        readiness: [ProviderID: ProviderReadiness]
    ) -> SharedCoreCapabilityResolution {
        let capabilityMatrix = CapabilityMatrix(manifest: manifest)
        let providerCapabilities = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { provider in
            let capability = capabilityMatrix.providerCapability(
                for: provider,
                profile: profile,
                availability: availability[provider] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[provider] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil)
            )
            return (provider, capability)
        })
        let featureCapabilities = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { feature in
            (feature, capabilityMatrix.featureCapability(for: feature, profile: profile))
        })
        return SharedCoreCapabilityResolution(
            providerCapabilities: providerCapabilities,
            featureCapabilities: featureCapabilities,
            effectiveProvider: capabilityMatrix.effectiveProvider(
                storedProvider: storedProvider,
                capabilities: providerCapabilities,
                fallbackOrder: fallbackOrder
            )
        )
    }

    func summarizeTriggerState(
        mode: TriggerMode,
        startResult: HotkeyStartResult
    ) -> TriggerStateSummary {
        currentTriggerMode = mode
        hotkeyIsPressed = false
        lastTapAt = nil
        return TriggerStateSummary(
            statusMessage: startResult.message ?? (startResult.isActive ? "Hotkey active." : "No global hotkey could be activated."),
            effectiveTriggerLabel: startResult.effectiveBinding.displayTitle,
            backendLabel: backendTitle(for: startResult.backend),
            fallbackReason: startResult.fallbackWasUsed ? startResult.message : nil,
            isAvailable: startResult.isActive
        )
    }

    func handleInputEvent(_ event: InputEvent, isRecording: Bool, timestamp: Date) -> DictationAction {
        switch currentTriggerMode {
        case .hold:
            switch event {
            case .triggerDown:
                guard hotkeyIsPressed == false else { return .none }
                hotkeyIsPressed = true
                return isRecording ? .none : .startRecording
            case .triggerUp:
                guard hotkeyIsPressed else { return .none }
                hotkeyIsPressed = false
                return isRecording ? .stopRecording : .none
            case .triggerToggle:
                return .none
            }
        case .toggle:
            return event == .triggerToggle || event == .triggerDown ? (isRecording ? .stopRecording : .startRecording) : .none
        case .doubleTapLock:
            guard event == .triggerToggle || event == .triggerDown else { return .none }
            if isRecording {
                lastTapAt = nil
                return .stopRecording
            }
            if let lastTapAt, timestamp.timeIntervalSince(lastTapAt) <= 0.35 {
                self.lastTapAt = nil
                return .startRecording
            }
            lastTapAt = timestamp
            return .none
        }
    }

    func resolveStyleDecision(context: ActiveAppContext, settings: StyleSettings) -> StyleDecisionReport {
        let focusedText = [
            context.focusedElementRole,
            context.focusedElementSubrole,
            context.focusedElementTitle,
            context.focusedElementPlaceholder,
            context.focusedElementDescription,
            context.focusedValueSnippet,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")

        let windowText = [context.windowTitle, context.appName, context.bundleID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        let category: StyleCategory
        let source: StyleDecisionSource
        let confidence: Double

        if matchesAny(focusedText, terms: ["to", "cc", "bcc", "subject", "compose", "draft", "send"]) {
            category = .email
            source = .focusedField
            confidence = 0.95
        } else if matchesAny(focusedText, terms: ["reply", "thread", "channel", "workspace", "team", "comment", "mention"]) {
            category = .workMessages
            source = .focusedField
            confidence = 0.92
        } else if matchesAny(focusedText, terms: ["dm", "direct message", "chat", "message", "reply"]) && matchesAny(windowText, terms: ["messages", "whatsapp", "telegram", "discord"]) {
            category = .personalMessages
            source = .focusedField
            confidence = 0.9
        } else if matchesAny(windowText, terms: ["gmail", "outlook", "mail", "inbox", "compose", "draft"]) {
            category = .email
            source = .windowTitle
            confidence = 0.82
        } else if matchesAny(windowText, terms: ["slack", "teams", "notion", "jira", "linear", "google chat", "channel", "thread", "workspace"]) {
            category = .workMessages
            source = .windowTitle
            confidence = 0.8
        } else if matchesAny(windowText, terms: ["messages", "whatsapp", "telegram", "discord", "dm", "direct message", "chat"]) {
            category = .personalMessages
            source = .windowTitle
            confidence = 0.78
        } else if matchesAny(windowText, terms: ["mail", "outlook", "spark", "hey", "slack", "teams", "messages", "whatsapp", "telegram", "discord", "notion", "jira", "linear"]) {
            category = context.styleCategory
            source = .bundleID
            confidence = 0.65
        } else {
            category = context.styleCategory
            source = .fallback
            confidence = 0.4
        }

        let configuration = settings.configuration(for: category)
        return StyleDecisionReport(
            timestamp: .now,
            category: category,
            preset: configuration.preset,
            source: source,
            confidence: confidence,
            formattingEnabled: configuration.enabled,
            reason: configuration.enabled ? nil : "Formatting is disabled for this category.",
            outputPreview: nil
        )
    }

    func processTranscript(
        text: String,
        context: ActiveAppContext?,
        settings: StyleSettings,
        resolvedDecision: StyleDecisionReport?
    ) -> SharedCoreProcessedTranscript {
        let decision = resolvedDecision ?? context.map { resolveStyleDecision(context: $0, settings: settings) } ?? StyleDecisionReport(
            timestamp: .now,
            category: .other,
            preset: settings.other.preset,
            source: .fallback,
            confidence: 0.4,
            formattingEnabled: settings.other.enabled,
            reason: settings.other.enabled ? nil : "Formatting is disabled for this category.",
            outputPreview: nil
        )
        let cleaned = cleanup(text)
        let final = applyStyle(cleaned, decision: decision)
        var report = decision
        report.timestamp = .now
        report.outputPreview = preview(final)
        return SharedCoreProcessedTranscript(cleanedText: cleaned, finalText: final, changed: cleaned != final, decision: report)
    }

    private func matchesAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func backendTitle(for backend: HotkeyBackend) -> String {
        switch backend {
        case .eventMonitor:
            return "Event monitor"
        case .functionKeySpecialCase:
            return "Fn / Globe"
        case .fallback:
            return "Fallback shortcut"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func cleanup(_ text: String) -> String {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var filtered: [String] = []
        var index = 0
        while index < tokens.count {
            let normalized = tokens[index].trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
            if normalized == "um" || normalized == "uh" {
                index += 1
                continue
            }
            if normalized == "you", index + 1 < tokens.count,
               tokens[index + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased() == "know" {
                index += 2
                continue
            }
            filtered.append(tokens[index])
            index += 1
        }
        return filtered.joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyStyle(_ text: String, decision: StyleDecisionReport) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return trimmed }
        guard decision.formattingEnabled else { return trimmed }
        switch decision.preset {
        case .formal:
            let capitalized = capitalize(trimmed)
            if let last = capitalized.last, [".", "!", "?"].contains(last) {
                return capitalized
            }
            return capitalized + "."
        case .casual:
            var value = capitalize(trimmed)
            if decision.category != .email, value.last == "." {
                value.removeLast()
            }
            return value
        case .enthusiastic:
            let capitalized = capitalize(trimmed)
            if capitalized.hasSuffix("!") {
                return capitalized
            }
            if capitalized.hasSuffix(".") || capitalized.hasSuffix("?") {
                return String(capitalized.dropLast()) + "!"
            }
            return capitalized + "!"
        case .veryCasual:
            var value = trimmed
            if let last = value.last, [".", "!"].contains(last) {
                value.removeLast()
            }
            if let first = value.first, String(first).uppercased() == String(first), String(first).lowercased() != String(first) {
                value.replaceSubrange(value.startIndex ... value.startIndex, with: String(first).lowercased())
            }
            return value
        }
    }

    private func capitalize(_ text: String) -> String {
        guard let range = text.rangeOfCharacter(from: .letters) else { return text }
        var output = text
        let character = output[range.lowerBound]
        output.replaceSubrange(range.lowerBound ... range.lowerBound, with: String(character).uppercased())
        return output
    }

    private func preview(_ text: String) -> String {
        let characters = Array(text)
        if characters.count <= 140 {
            return text
        }
        return String(characters.prefix(140)) + "…"
    }
}
