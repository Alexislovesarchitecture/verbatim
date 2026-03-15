import SwiftUI

struct InlineStatusBanner: View {
    let status: InlineStatusMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.tone == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(status.tone == .warning ? AppSectionAccent.amber.tint : AppSectionAccent.cobalt.tint)

            Text(status.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .applyLiquidCardStyle(cornerRadius: 20, tone: .frost, padding: 0)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

struct ProviderSelectionButtonsView: View {
    @EnvironmentObject private var model: AppModel

    private let providerOrder: [ProviderID] = [.whisper, .parakeet, .appleSpeech]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(providerOrder) { provider in
                let capability = model.providerCapability(for: provider)

                Button {
                    model.selectProvider(provider)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: providerSystemImage(provider))
                            .font(.system(size: 13, weight: .semibold))
                        Text(provider.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(model.settings.selectedProvider == provider ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .opacity(capability.isSupported ? 1 : 0.62)
                    .applySelectionPillStyle(selected: model.settings.selectedProvider == provider, accent: .cobalt, cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .disabled(model.canSelectProvider(provider) == false)
            }
        }
    }

    private func providerSystemImage(_ provider: ProviderID) -> String {
        switch provider {
        case .whisper:
            return "waveform"
        case .parakeet:
            return "antenna.radiowaves.left.and.right"
        case .appleSpeech:
            return "apple.logo"
        }
    }
}

struct HotkeysPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsPanelCard(title: "Global Hotkey") {
            Toggle(isOn: Binding(
                get: { model.settings.hotkeyEnabled },
                set: { model.updateHotkeyEnabled($0) }
            )) {
                Text("Enable global activation")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .toggleStyle(.switch)
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            Picker("Trigger mode", selection: Binding(
                get: { model.settings.hotkeyTriggerMode },
                set: { model.updateHotkeyTriggerMode($0) }
            )) {
                ForEach(HotkeyTriggerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)

            HStack(spacing: 10) {
                HotkeyRecorderField(shortcut: Binding(
                    get: { model.settings.hotkeyBinding },
                    set: { model.updateHotkeyBinding($0) }
                ))
                .frame(width: 220, height: 36)

                Button(model.isCapturingHotkey ? "Capturing…" : "Capture") {
                    model.beginHotkeyCapture()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(model.isCapturingHotkey || model.settings.hotkeyEnabled == false)

                Button("Use Fn / Globe") {
                    model.resetHotkeyBindingToDefault()
                }
                .applyGlassButtonStyle()
                .disabled(model.settings.hotkeyEnabled == false)
            }
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            if model.settings.hotkeyBinding.usesFn {
                Picker("Fn / Globe fallback", selection: Binding(
                    get: { model.settings.functionKeyFallbackMode },
                    set: { model.updateFunctionKeyFallbackMode($0) }
                )) {
                    ForEach(FunctionKeyFallbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)
            }

            Text("Requested binding: \(model.settings.hotkeyBinding.displayTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Effective binding: \(model.hotkeyEffectiveBindingTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Backend: \(model.hotkeyBackendTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if let fallbackReason = model.hotkeyFallbackReason, fallbackReason.isEmpty == false {
                Text(fallbackReason)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }

            Text(model.hotkeyStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if model.featureCapability(for: .hotkeyCapture).isSupported == false {
                Text(model.featureCapability(for: .hotkeyCapture).detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }
        }
    }
}

struct TranscriptionSettingsPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VerbatimGlassGroup(spacing: 18) {
            SettingsPanelCard(title: "Speech to Text") {
                ProviderSelectionButtonsView()

                if let message = model.effectiveProviderMessage {
                    Text(message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppSectionAccent.amber.tint)
                }

                providerSettingsContent
            }

            SettingsPanelCard(title: "Preferred Language") {
                Picker("Language", selection: Binding(
                    get: { model.settings.preferredLanguage },
                    set: { model.settings.preferredLanguage = $0 }
                )) {
                    ForEach(model.currentLanguageOptions) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            SettingsPanelCard(title: "Dictionary") {
                Text("Manage vocabulary hints in Dictionary. Whisper uses these as prompt context when possible. Apple Speech may ignore them in v1, and Parakeet ignores them in v1.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Button("Open Dictionary") {
                    model.selectAppTab(.dictionary)
                    model.closeSettings()
                }
                .applyGlassButtonStyle()
            }
        }
    }

    @ViewBuilder
    private var providerSettingsContent: some View {
        switch model.settings.selectedProvider {
        case .whisper:
            providerStatusHeader(for: .whisper)
            if model.providerCapability(for: .whisper).isSupported {
                ForEach(model.whisperModelStatuses) { status in
                    modelRow(
                        status,
                        selected: model.settings.selectedWhisperModelID == status.id,
                        onSelect: { model.settings.selectedWhisperModelID = status.id },
                        onDownload: { Task { await model.downloadWhisperModel(status.id) } },
                        onDelete: { Task { await model.deleteWhisperModel(status.id) } }
                    )
                }
            }
        case .parakeet:
            providerStatusHeader(for: .parakeet)
            if model.providerCapability(for: .parakeet).isSupported {
                ForEach(model.parakeetModelStatuses) { status in
                    modelRow(
                        status,
                        selected: model.settings.selectedParakeetModelID == status.id,
                        onSelect: { model.settings.selectedParakeetModelID = status.id },
                        onDownload: { Task { await model.downloadParakeetModel(status.id) } },
                        onDelete: { Task { await model.deleteParakeetModel(status.id) } }
                    )
                }
            }
        case .appleSpeech:
            providerStatusHeader(for: .appleSpeech)
            if model.providerCapability(for: .appleSpeech).isSupported,
               model.providerStatus(for: .appleSpeech).actionTitle == "Install" {
                Button("Install Apple Speech Assets") {
                    Task { await model.installAppleAssets() }
                }
                .applyGlassButtonStyle(prominent: true)
            }
            if model.providerCapability(for: .appleSpeech).isSupported {
                Text("\(model.appleInstalledLanguages.count) Apple speech languages are currently installed on this Mac.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
    }

    private func providerStatusHeader(for provider: ProviderID) -> some View {
        let capability = model.providerCapability(for: provider)
        let statusMessage = capability.kind == .unsupported ? capability.detail : model.providerStatus(for: provider).message

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(provider.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Text(capability.kind.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(capability.isAvailable ? AppSectionAccent.mint.tint : AppSectionAccent.amber.tint)
                    .applyStatusBadgeEffect()
            }

            Text(statusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private func modelRow(
        _ status: ModelStatus,
        selected: Bool,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.descriptor.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if status.descriptor.recommended {
                        Text("Recommended")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppSectionAccent.mint.tint)
                            .applyStatusBadgeEffect()
                    }
                }
                Text("\(status.descriptor.detail) • \(status.descriptor.sizeLabel)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer()

            switch status.state {
            case .ready:
                Button(selected ? "Active" : "Select", action: onSelect)
                    .applyGlassButtonStyle(prominent: selected == false)
                Button("Delete", action: onDelete)
                    .applyGlassButtonStyle()
            case .downloading:
                Text("Downloading…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            case .installing:
                Text("Installing…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red)
            case .notInstalled:
                Button("Download", action: onDownload)
                    .applyGlassButtonStyle(prominent: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? AppSectionAccent.cobalt.glow : Color.white.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? AppSectionAccent.cobalt.tint.opacity(0.28) : Color.white.opacity(0.28), lineWidth: 1)
        )
    }
}

struct PreferencesSettingsPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VerbatimGlassGroup(spacing: 18) {
            SettingsPanelCard(title: "Behavior") {
                Toggle("Show floating overlay", isOn: Binding(
                    get: { model.settings.showOverlay },
                    set: { model.settings.showOverlay = $0 }
                ))

                Picker("After transcription", selection: Binding(
                    get: { model.settings.pasteMode },
                    set: { model.settings.pasteMode = $0 }
                )) {
                    ForEach(PasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(model.featureCapability(for: .autoPaste).isSupported == false)

                if model.featureCapability(for: .autoPaste).isSupported == false {
                    Text(model.featureCapability(for: .autoPaste).detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppSectionAccent.amber.tint)
                }

                Toggle("Show menu bar item", isOn: Binding(
                    get: { model.settings.menuBarEnabled },
                    set: { model.settings.menuBarEnabled = $0 }
                ))
            }

            SettingsPanelCard(title: "Utilities") {
                Text("Local storage")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(model.paths.rootURL.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Reveal Application Support") {
                        model.revealAppSupport()
                    }
                    .applyGlassButtonStyle()

                    Button("Replay Onboarding") {
                        model.resetOnboarding()
                    }
                    .applyGlassButtonStyle()
                }

                Button("Reset Local Data") {
                    model.resetAppData()
                }
                .applyGlassButtonStyle(prominent: true)
            }
        }
    }
}

struct PrivacySettingsPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VerbatimGlassGroup(spacing: 18) {
            SettingsPanelCard(title: "Permissions") {
                permissionRow(
                    title: "Microphone",
                    subtitle: "Required for local recording and transcription.",
                    granted: model.permissionsManager.microphoneAuthorized,
                    actionTitle: model.permissionsManager.microphoneAuthorized ? "Granted" : "Grant"
                ) {
                    Task { await model.requestMicrophone() }
                }

                permissionRow(
                    title: "Accessibility",
                    subtitle: "Needed for global hotkeys and automatic paste after transcription.",
                    granted: model.permissionsManager.accessibilityAuthorized,
                    actionTitle: model.permissionsManager.accessibilityAuthorized ? "Granted" : "Grant"
                ) {
                    model.promptAccessibility()
                }
            }

            SettingsPanelCard(title: "Privacy") {
                Text("Verbatim stores transcripts, dictionary entries, and local models on this Mac only. No cloud sync, billing, or account features are present in this build.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Open Microphone Settings") {
                        model.permissionsManager.openMicrophoneSettings()
                    }
                    .applyGlassButtonStyle()

                    Button("Open Accessibility Settings") {
                        model.permissionsManager.openAccessibilitySettings()
                    }
                    .applyGlassButtonStyle()
                }
            }

            SettingsPanelCard(title: "Diagnostics") {
                Text("Preflighted local runtime, selected model, and provider readiness state.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Re-check") {
                        Task { await model.recheckDiagnostics() }
                    }
                    .applyGlassButtonStyle(prominent: true)

                    Button("Reveal Logs") {
                        model.revealLogs()
                    }
                    .applyGlassButtonStyle()

                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                    .applyGlassButtonStyle()
                }

                ForEach([ProviderID.whisper, .parakeet, .appleSpeech]) { provider in
                    if let diagnostic = model.providerDiagnostic(for: provider) {
                        diagnosticRow(diagnostic)
                    }
                }
            }
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer()

            Button(actionTitle, action: action)
                .applyGlassButtonStyle(prominent: granted == false)
                .disabled(granted)
        }
    }

    private func diagnosticRow(_ diagnostic: ProviderDiagnosticStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(diagnostic.provider.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        Text(diagnostic.readiness.kind == .ready ? "Ready" : "Attention")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(diagnostic.readiness.kind == .ready ? AppSectionAccent.mint.tint : AppSectionAccent.amber.tint)
                            .applyStatusBadgeEffect()
                    }

                    Text("Selected: \(diagnostic.selectionDescription)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    Text("Availability: \(diagnostic.availability.isAvailable ? "Available" : "Unavailable")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    if let snapshot = diagnostic.runtimeSnapshot {
                        Text("Runtime: \(snapshot.binaryPresent ? "Binary present" : "Binary missing") • \(snapshot.state.rawValue.capitalized)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    } else {
                        Text("Runtime: System managed")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let source = diagnostic.selectionSource {
                        Text("Install source: \(source.title)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let lastCheck = diagnostic.lastCheck {
                        Text("Last checked: \(lastCheck.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let error = diagnostic.lastError, error.isEmpty == false {
                        Text(error)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(diagnostic.readiness.message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if diagnostic.provider != .appleSpeech {
                        Button("Restart Runtime") {
                            Task { await model.restartRuntime(for: diagnostic.provider) }
                        }
                        .applyGlassButtonStyle(prominent: true)
                        .disabled(diagnostic.selectionInstalled == false || diagnostic.runtimeSnapshot?.binaryPresent != true)
                    } else if diagnostic.readiness.actionTitle == "Install" {
                        Button("Install") {
                            Task { await model.installAppleAssets() }
                        }
                        .applyGlassButtonStyle(prominent: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }
}

struct SupportOverlayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Quick help for hotkeys, permissions, and local runtime setup.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Button {
                    model.closeSupport()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .padding(10)
                        .applySelectionPillStyle(selected: false, accent: .violet, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            SupportCardView(
                title: "Hotkey",
                subtitle: "Current global shortcut",
                detail: [
                    "Requested: \(model.settings.hotkeyBinding.displayTitle)",
                    "Effective: \(model.hotkeyEffectiveBindingTitle)",
                    "Backend: \(model.hotkeyBackendTitle)",
                    "Trigger mode: \(model.settings.hotkeyTriggerMode.title)",
                    model.hotkeyFallbackReason,
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            )

            SupportCardView(
                title: "Permissions",
                subtitle: "Microphone is required. Accessibility is optional unless you want auto-paste.",
                detail: [
                    "Microphone: \(model.permissionsManager.microphoneAuthorized ? "Granted" : "Missing")",
                    "Accessibility: \(model.permissionsManager.accessibilityAuthorized ? "Granted" : "Missing")",
                ]
                .joined(separator: "\n")
            )

            SupportCardView(
                title: "Storage",
                subtitle: "Local history, dictionary, models, and logs live here.",
                detail: model.paths.rootURL.path
            )

            SupportCardView(
                title: "Local Runtimes",
                subtitle: "Whisper uses whisper-server, Parakeet uses sherpa-onnx, and Apple Speech uses macOS system assets.",
                detail: "Everything continues to work offline after models and Apple language assets are installed.\n\(model.providerPrewarmStatusMessage)"
            )

            SupportCardView(
                title: "Diagnostics",
                subtitle: "Current provider/runtime summary",
                detail: model.supportDiagnosticsSummary.isEmpty ? "Checking local runtime state…" : model.supportDiagnosticsSummary
            )

            HStack(spacing: 10) {
                Button("Re-check") {
                    Task { await model.recheckDiagnostics() }
                }
                .applyGlassButtonStyle(prominent: true)

                Button("Reveal Logs") {
                    model.revealLogs()
                }
                .applyGlassButtonStyle()

                Button("Copy Diagnostics") {
                    model.copyDiagnostics()
                }
                .applyGlassButtonStyle()

                Button("Reveal Application Support") {
                    model.revealAppSupport()
                }
                .applyGlassButtonStyle()

                Button("Microphone Settings") {
                    model.permissionsManager.openMicrophoneSettings()
                }
                .applyGlassButtonStyle()

                Button("Accessibility Settings") {
                    model.permissionsManager.openAccessibilitySettings()
                }
                .applyGlassButtonStyle()
            }

            HStack {
                Spacer()
                Button("Close") {
                    model.closeSupport()
                }
                .applyGlassButtonStyle(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 560)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .shell, padding: 0)
        .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 18)
    }
}

private struct SupportCardView: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: 16)
    }
}

struct SettingsPanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: 24, tone: .frost, padding: 16)
    }
}
